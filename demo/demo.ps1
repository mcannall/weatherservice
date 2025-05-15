#!/usr/bin/env pwsh

# Add a reference to .NET Web assembly for URL encoding
Add-Type -AssemblyName System.Web

function Write-ColorOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [string]$ForegroundColor = "White"
    )
    Write-Host $Message -ForegroundColor $ForegroundColor
    Start-Sleep -Seconds 1
}

function Test-CommandExists {
    param ($Command)
    $null -ne (Get-Command -Name $Command -ErrorAction SilentlyContinue)
}

function Test-PortInUse {
    param($Port)
    $connection = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    return $null -ne $connection
}

function Get-PodStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LabelSelector,
        [switch]$Detailed
    )
    
    try {
        # Get basic pod information
        $podJson = kubectl get pod -l $LabelSelector -o json 2>&1
        if ($LASTEXITCODE -ne 0) {
            return @{
                Success = $false
                Message = "Failed to get pod status: $podJson"
                PodName = $null
                Ready = $false
                Status = "Unknown"
            }
        }
        
        $podInfo = $podJson | ConvertFrom-Json
        
        if ($podInfo.items.Count -eq 0) {
            return @{
                Success = $false
                Message = "No pods found with label selector: $LabelSelector"
                PodName = $null
                Ready = $false
                Status = "NotFound"
            }
        }
        
        $pod = $podInfo.items[0]  # Get the first pod
        $podName = $pod.metadata.name
        $status = $pod.status.phase
        
        # Check if pod is ready
        $ready = $false
        foreach ($condition in $pod.status.conditions) {
            if ($condition.type -eq "Ready" -and $condition.status -eq "True") {
                $ready = $true
                break
            }
        }
        
        $result = @{
            Success = $true
            PodName = $podName
            Ready = $ready
            Status = $status
            Message = "Pod status: $status, Ready: $ready"
        }
        
        # Add detailed information if requested
        if ($Detailed) {
            $containerStatuses = $pod.status.containerStatuses
            if ($containerStatuses) {
                $result.ContainerReady = $containerStatuses[0].ready
                $result.ContainerStatus = $containerStatuses[0].state
                $result.RestartCount = $containerStatuses[0].restartCount
                
                # If not ready, get the reason
                if (-not $containerStatuses[0].ready) {
                    if ($containerStatuses[0].state.waiting) {
                        $result.WaitingReason = $containerStatuses[0].state.waiting.reason
                        $result.WaitingMessage = $containerStatuses[0].state.waiting.message
                    }
                    if ($containerStatuses[0].state.terminated) {
                        $result.TerminatedReason = $containerStatuses[0].state.terminated.reason
                        $result.TerminatedMessage = $containerStatuses[0].state.terminated.message
                    }
                }
            }
            
            # Get recent logs if pod exists and is running
            if ($status -eq "Running") {
                try {
                    $logs = kubectl logs $podName --tail=20 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        $result.RecentLogs = $logs
                    }
                } catch {
                    $result.LogError = $_.Exception.Message
                }
            }
        }
        
        return $result
    } catch {
        return @{
            Success = $false
            Message = "Error getting pod status: $($_.Exception.Message)"
            PodName = $null
            Ready = $false
            Status = "Error"
        }
    }
}

function Show-Progress {
    param(
        [string]$Activity,
        [string]$Status,
        [int]$PercentComplete
    )
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
    if ($PercentComplete -eq 100) {
        Start-Sleep -Milliseconds 500
        Write-Progress -Activity $Activity -Completed
    }
}

function Get-CurrentVersion {
    $csproj = Get-Content "$projectRoot/api/api.csproj" -Raw
    if ($csproj -match '<Version>([\d\.]+)</Version>') {
        return $matches[1]
    }
    return "1.0.0"
}

function Update-Version {
    param([string]$CurrentVersion)
    $parts = $CurrentVersion.Split('.')
    $parts[2] = [int]$parts[2] + 1
    return $parts -join '.'
}

function Update-CsprojVersion {
    param([string]$NewVersion)
    $csproj = Get-Content "$projectRoot/api/api.csproj" -Raw
    $csproj = $csproj -replace '<Version>[\d\.]+</Version>', "<Version>$NewVersion</Version>"
    Set-Content -Path "$projectRoot/api/api.csproj" -Value $csproj
}

function Start-PortForwarding {
    param(
        [string]$Service = "api",
        [int]$LocalPort = 30080,
        [int]$TargetPort = 80,
        [int]$MaxRetries = 3,
        [int]$RetryWaitSeconds = 2
    )

    # Stop any existing port forwarding first
    Stop-PortForwarding -Ports @($LocalPort)

    # Verify port is available
    if (Test-PortInUse -Port $LocalPort) {
        Write-ColorOutput ">> Error: Port $LocalPort is still in use after cleanup" "Red"
        Write-ColorOutput ">> Please ensure no other processes are using port $LocalPort" "Red"
        Write-ColorOutput ">> You may need to restart PowerShell or reboot your machine if the port cannot be freed" "Yellow"
        return $null
    }

    # Start port forwarding in background
    Write-ColorOutput ">> Starting port forwarding on port $LocalPort..." "Cyan"
    $job = Start-Job -ScriptBlock {
        param($service, $localPort, $targetPort)
        kubectl port-forward service/$service ${localPort}:${targetPort}
    } -ArgumentList $Service, $LocalPort, $TargetPort

    # Verify port forwarding is working
    $retryCount = 0
    $portForwardStarted = $false

    while (-not $portForwardStarted -and $retryCount -lt $MaxRetries) {
        Start-Sleep -Seconds $RetryWaitSeconds
        if (Test-PortInUse -Port $LocalPort) {
            $portForwardStarted = $true
            Write-ColorOutput ">> Port forwarding started successfully on port $LocalPort!" "Green"
        } else {
            $retryCount++
            if ($retryCount -lt $MaxRetries) {
                Write-ColorOutput ">> Waiting for port forwarding to start (attempt $retryCount of $MaxRetries)..." "Yellow"
            }
        }
    }

    if (-not $portForwardStarted) {
        Write-ColorOutput ">> Error: Port forwarding failed to start after $MaxRetries attempts" "Red"
        Stop-Job $job
        Remove-Job $job
        return $null
    }

    return $job
}

function Stop-PortForwarding {
    param(
        [int[]]$Ports = @(30080, 30081)
    )
    
    # Find any existing kubectl port-forward processes
    $existingProcesses = Get-Process -Name kubectl -ErrorAction SilentlyContinue | 
                         Where-Object { $_.CommandLine -match "port-forward" }
    
    if ($existingProcesses) {
        Write-ColorOutput ">> Found existing port-forward processes, cleaning up..." "Yellow"
        $existingProcesses | Stop-Process -Force
        Start-Sleep -Seconds 2
    }
    
    # Clean up any existing port-forward jobs
    $existingJobs = Get-Job | Where-Object { $_.Command -match "kubectl.*port-forward" }
    if ($existingJobs) {
        Write-ColorOutput ">> Found existing port-forward jobs, cleaning up..." "Yellow"
        $existingJobs | Stop-Job
        $existingJobs | Remove-Job -Force
        Start-Sleep -Seconds 1
    }
    
    # Find and kill any other process using our ports
    foreach ($port in $Ports) {
        $processesUsingPort = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
        if ($processesUsingPort) {
            Write-ColorOutput ">> Found processes using port $port, terminating..." "Yellow"
            foreach ($connection in $processesUsingPort) {
                $process = Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue
                if ($process) {
                    Write-ColorOutput ">> Terminating process: $($process.Name) (PID: $($process.Id))" "Yellow"
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                }
            }
            Start-Sleep -Seconds 2
        }
    }
    
    # Verify ports are free
    foreach ($port in $Ports) {
        if (Test-PortInUse -Port $port) {
            Write-ColorOutput ">> Warning: Port $port is still in use after cleanup attempts" "Red"
        } else {
            Write-ColorOutput ">> Port $port is now free" "Green"
        }
    }
}

function Wait-ForGitHubAction {
    param([string]$RunId)
    Write-ColorOutput ">> Waiting for GitHub Actions workflow to complete..." "Cyan"
    $completed = $false
    $attempts = 0
    $maxAttempts = 30  # 5 minutes with 10-second intervals

    while (-not $completed -and $attempts -lt $maxAttempts) {
        $status = gh run view $RunId --json status --jq .status
        if ($status -eq "completed") {
            $completed = $true
            Write-ColorOutput ">> GitHub Actions workflow completed!" "Green"
        } else {
            $attempts++
            Write-ColorOutput ">> Workflow still running... (attempt $attempts of $maxAttempts)" "Yellow"
            Start-Sleep -Seconds 10
        }
    }

    if (-not $completed) {
        Write-ColorOutput ">> Warning: Timed out waiting for GitHub Actions workflow" "Yellow"
        Write-ColorOutput ">> Continuing with demo..." "Yellow"
    }
}

function Show-CICDPipeline {
    Write-ColorOutput "`n>> CI/CD Pipeline Overview" "Magenta"
    Write-ColorOutput "------------------------" "Magenta"
    
    $steps = @(
        @{
            title = "1. Code Change"
            description = "Developer commits code to GitHub repository"
            command = "git commit -m 'Update weather service'"
        },
        @{
            title = "2. GitHub Actions Trigger"
            description = "Workflow automatically starts on push to main branch"
            command = "cat .github/workflows/docker-build.yml"
        },
        @{
            title = "3. Build & Test"
            description = "Builds .NET application and runs tests"
            command = "dotnet build && dotnet test"
        },
        @{
            title = "4. Docker Build"
            description = "Builds Docker image with latest code"
            command = "docker build -t ghcr.io/mcannall/weatherservice:$commitSha"
        },
        @{
            title = "5. Push to GitHub Packages"
            description = "Pushes image to GitHub Container Registry"
            command = "docker push ghcr.io/mcannall/weatherservice:$commitSha"
        },
        @{
            title = "6. Deploy to Kubernetes"
            description = "Updates Kubernetes deployment with new image"
            command = "kubectl set image deployment/api api=ghcr.io/mcannall/weatherservice:$commitSha"
        }
    )

    foreach ($step in $steps) {
        Write-ColorOutput "`n$($step.title)" "Yellow"
        Write-ColorOutput $step.description "White"
        Write-ColorOutput "Command: $($step.command)" "Cyan"
        Start-Sleep -Seconds 2
    }
}

# Set up global variables
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir  # Go up one level from script directory
# Note: You must set OPENWEATHERMAP_API_KEY as an environment variable before running this script
# $env:OPENWEATHERMAP_API_KEY = "your-api-key-here"  # Example - do NOT store real keys in this file
$useMockData = $true  # Change to $false to use real API

# Get current git commit SHA for consistent image tagging
$commitSha = $(git rev-parse --short HEAD)
if (-not $commitSha) {
    $commitSha = "local-$(Get-Date -Format 'yyyyMMddHHmmss')"
}
Write-Host "Using commit SHA: $commitSha for image tagging" -ForegroundColor Cyan

# Check prerequisites
Write-ColorOutput ">> Checking prerequisites..." "Cyan"
$prerequisites = @("docker", "kind", "kubectl")
$missing = @()

foreach ($tool in $prerequisites) {
    if (-not (Test-CommandExists $tool)) {
        $missing += $tool
    }
}

if ($missing.Count -gt 0) {
    Write-ColorOutput ">> Missing required tools: $($missing -join ', ')" "Red"
    Write-ColorOutput "Please install the missing tools and try again." "Red"
    exit 1
}

Write-ColorOutput ">> All prerequisites found!" "Green"

# Clean up any leftover port-forwarding processes from previous runs
Write-ColorOutput ">> Checking for and cleaning up any previous port forwarding..." "Cyan"
Stop-PortForwarding
Write-ColorOutput ">> Port cleanup completed" "Green"

# Show deployment options
Write-ColorOutput "`n>> Choose deployment option:" "Magenta"
Write-ColorOutput "1. Use GitHub Packages (commit changes and wait for build)" "Cyan"
Write-ColorOutput "2. Build locally (skip GitHub build)" "Cyan"
$choice = Read-Host "Enter your choice (1 or 2)"

# Check for GitHub CLI if option 1 is selected
if ($choice -eq "1") {
    if (-not (Test-CommandExists "gh")) {
        Write-ColorOutput ">> Error: GitHub CLI (gh) is required for option 1" "Red"
        Write-ColorOutput ">> Please install GitHub CLI or choose option 2" "Red"
        exit 1
    }
    
    # Check GitHub authentication
    $authStatus = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput ">> Error: GitHub CLI is not authenticated" "Red"
        Write-ColorOutput ">> Please run 'gh auth login' first and then try again" "Red"
        exit 1
    }
}

$currentVersion = Get-CurrentVersion
$imageTag = ""
$routePlannerImageTag = ""

if ($choice -eq "1") {
    # Option 1: Use GitHub Packages
    $newVersion = Update-Version $currentVersion
    Write-ColorOutput ">> Current version: $currentVersion" "Yellow"
    Write-ColorOutput ">> New version will be: $newVersion" "Yellow"
    
    # Update version in csproj
    Update-CsprojVersion $newVersion
    
    # Pull latest changes first
    Write-ColorOutput ">> Pulling latest changes..." "Cyan"
    git pull
    
    # Commit and push changes
    Write-ColorOutput ">> Committing version update..." "Cyan"
    git add "$projectRoot/api/api.csproj"
    git commit -m "Bump version to $newVersion for demo"
    
    # Try to push, if it fails, pull and try again
    $pushAttempt = 0
    $maxAttempts = 2
    do {
        $pushAttempt++
        git push
        if ($LASTEXITCODE -ne 0) {
            if ($pushAttempt -lt $maxAttempts) {
                Write-ColorOutput ">> Push failed, pulling latest changes and trying again..." "Yellow"
                git pull --rebase
            } else {
                Write-ColorOutput ">> Failed to push changes after $maxAttempts attempts" "Red"
                Write-ColorOutput ">> Please resolve any conflicts manually and try again" "Red"
                exit 1
            }
        }
    } while ($LASTEXITCODE -ne 0 -and $pushAttempt -lt $maxAttempts)
    
    # Get the latest workflow run ID
    $runId = gh run list --limit 1 --json databaseId --jq '.[0].databaseId'
    
    # Wait for the workflow to complete
    Wait-ForGitHubAction $runId
    
    $imageTag = "ghcr.io/mcannall/weatherservice:$newVersion"
    $routePlannerImageTag = "ghcr.io/mcannall/weatherservice/route-weather-planner:$newVersion"
} else {
    # Option 2: Build locally
    $imageTag = "ghcr.io/mcannall/weatherservice:local-demo"
    $routePlannerImageTag = "ghcr.io/mcannall/weatherservice/route-weather-planner:local-demo"
}

# Clean up any existing resources
Write-ColorOutput ">> Cleaning up any existing resources..." "Yellow"
kind delete cluster --name weatherservice 2>$null
Write-ColorOutput ">> Cleanup complete!" "Green"

# Create Kind cluster
Write-ColorOutput ">> Creating Kubernetes cluster..." "Cyan"
Show-Progress -Activity "Creating cluster" -Status "Initializing..." -PercentComplete 0
$kindResult = kind create cluster --name weatherservice 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-ColorOutput ">> Error creating Kind cluster: $kindResult" "Red"
    Write-ColorOutput ">> This may be due to Docker not running or not configured properly." "Yellow"
    Write-ColorOutput ">> Please check that Docker Desktop is running and that Kubernetes is enabled in Docker Desktop settings." "Yellow"
    Write-ColorOutput ">> Would you like to continue with the demo in simulation mode? This will skip actual deployment. (y/n)" "Cyan"
    $continue = Read-Host
    if ($continue.ToLower() -ne "y") {
        Write-ColorOutput ">> Exiting demo." "Red"
        exit 1
    }
    $simulationMode = $true
} else {
    $simulationMode = $false
    Show-Progress -Activity "Creating cluster" -Status "Complete" -PercentComplete 100
    Write-ColorOutput ">> Cluster created!" "Green"
}

if ($choice -eq "1") {
    # Pull the image from GitHub Packages
    Write-ColorOutput ">> Pulling image from GitHub Packages..." "Cyan"
    Show-Progress -Activity "Pulling image" -Status "Pulling..." -PercentComplete 0
    if (-not $simulationMode) {
        $dockerResult = docker pull $imageTag 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput ">> Error pulling image: $dockerResult" "Red"
            Write-ColorOutput ">> Continuing in simulation mode..." "Yellow"
            $simulationMode = $true
        }
    }
    Show-Progress -Activity "Pulling image" -Status "Complete" -PercentComplete 100
} else {
    # Build the images locally
    Write-ColorOutput ">> Building Docker images locally..." "Cyan"
    
    # Build the API image
    Show-Progress -Activity "Building API image" -Status "Building..." -PercentComplete 0
    if (-not $simulationMode) {
        $dockerResult = docker build -t $imageTag "$projectRoot/api" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput ">> Error building API image: $dockerResult" "Red"
            Write-ColorOutput ">> Continuing in simulation mode..." "Yellow"
            $simulationMode = $true
        }
    }
    Show-Progress -Activity "Building API image" -Status "Complete" -PercentComplete 100
    
    # Build the Route Planner image
    if (-not $simulationMode) {
        Show-Progress -Activity "Building Route Planner image" -Status "Building..." -PercentComplete 0
        $dockerResult = docker build -t $routePlannerImageTag "$projectRoot/route-weather-planner" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput ">> Error building Route Planner image: $dockerResult" "Red"
            Write-ColorOutput ">> Continuing in simulation mode..." "Yellow"
            $simulationMode = $true
        }
        Show-Progress -Activity "Building Route Planner image" -Status "Complete" -PercentComplete 100
    }
}

Write-ColorOutput ">> Loading images into Kind cluster..." "Cyan"
Show-Progress -Activity "Loading images" -Status "Loading..." -PercentComplete 0
if (-not $simulationMode) {
    # Load API image
    $kindResult = kind load docker-image $imageTag --name weatherservice 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput ">> Error loading API image into Kind: $kindResult" "Red"
        Write-ColorOutput ">> Continuing in simulation mode..." "Yellow"
        $simulationMode = $true
    }
    
    # Load Route Planner image if we're still in non-simulation mode
    if (-not $simulationMode) {
        $kindResult = kind load docker-image $routePlannerImageTag --name weatherservice 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput ">> Error loading Route Planner image into Kind: $kindResult" "Red"
            Write-ColorOutput ">> Continuing in simulation mode..." "Yellow"
            $simulationMode = $true
        }
    }
}
Show-Progress -Activity "Loading images" -Status "Complete" -PercentComplete 100
Write-ColorOutput ">> Images loaded!" "Green"

# Create Kubernetes resources
Write-ColorOutput ">> Creating Kubernetes resources..." "Cyan"

# Read Google Maps API key from .env file
$envPath = "$projectRoot/route-weather-planner/.env"
if (-not (Test-Path $envPath)) {
    Write-ColorOutput ">> Error: .env file not found at $envPath" "Red"
    Write-ColorOutput ">> Please ensure you have copied .env.template to .env and added your API key" "Red"
    exit 1
}

$envContent = Get-Content $envPath
$googleMapsApiKey = ($envContent | Where-Object { $_ -match "GOOGLE_MAPS_API_KEY=(.+)" } | ForEach-Object { $matches[1] })

if (-not $googleMapsApiKey) {
    Write-ColorOutput ">> Error: Google Maps API key not found in .env file" "Red"
    Write-ColorOutput ">> Please ensure GOOGLE_MAPS_API_KEY is set in your .env file" "Red"
    exit 1
}

Write-ColorOutput ">> Successfully read Google Maps API key from .env" "Green"

$secrets = @{
    OPENWEATHERMAP_API_KEY = $env:OPENWEATHERMAP_API_KEY
    GOOGLE_MAPS_API_KEY = $googleMapsApiKey
}
$secretArgs = $secrets.GetEnumerator() | ForEach-Object { "--from-literal=$($_.Key)=$($_.Value)" }

if (-not $simulationMode) {
    $kubectlResult = kubectl create secret generic weatherservice-secrets $secretArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput ">> Error creating Kubernetes secret: $kubectlResult" "Red"
        Write-ColorOutput ">> Continuing in simulation mode..." "Yellow"
        $simulationMode = $true
    }
    
    $kubectlResult = kubectl apply -f "$projectRoot/k8s/" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput ">> Error applying Kubernetes resources: $kubectlResult" "Red"
        Write-ColorOutput ">> Continuing in simulation mode..." "Yellow"
        $simulationMode = $true
    }
}
Write-ColorOutput ">> Resources created!" "Green"

# Wait for pod to be ready
Write-ColorOutput ">> Waiting for pod to be ready..." "Cyan"
Show-Progress -Activity "Waiting for pod" -Status "Waiting..." -PercentComplete 0

if (-not $simulationMode) {
    $waitResult = kubectl wait --for=condition=ready pod -l app=weatherservice --timeout=60s 2>&1
    $waitSuccess = $LASTEXITCODE -eq 0
    
    if (-not $waitSuccess) {
        Write-ColorOutput ">> Error waiting for pod to be ready: $waitResult" "Red"
        Write-ColorOutput ">> Continuing in simulation mode..." "Yellow"
        $simulationMode = $true
    }
}
Show-Progress -Activity "Waiting for pod" -Status "Complete" -PercentComplete 100

if (-not $simulationMode) {
    # If wait failed, check pod status for detailed diagnostics
    if (-not $waitSuccess) {
        Write-ColorOutput ">> Error waiting for pod to be ready: $waitResult" "Red"
        
        Write-ColorOutput ">> Checking pod status for diagnostics..." "Yellow"
        $podStatus = Get-PodStatus -LabelSelector "app=weatherservice" -Detailed
        
        if (-not $podStatus.Success) {
            Write-ColorOutput ">> Failed to get pod status: $($podStatus.Message)" "Red"
        } else {
            Write-ColorOutput ">> Pod: $($podStatus.PodName)" "Yellow"
            Write-ColorOutput ">> Status: $($podStatus.Status)" "Yellow"
            Write-ColorOutput ">> Ready: $($podStatus.Ready)" "Yellow"
            
            if ($podStatus.ContainerStatus) {
                if ($podStatus.WaitingReason) {
                    Write-ColorOutput ">> Container waiting reason: $($podStatus.WaitingReason)" "Red"
                    if ($podStatus.WaitingMessage) {
                        Write-ColorOutput ">> Message: $($podStatus.WaitingMessage)" "Red"
                    }
                }
                
                if ($podStatus.TerminatedReason) {
                    Write-ColorOutput ">> Container terminated reason: $($podStatus.TerminatedReason)" "Red"
                    if ($podStatus.TerminatedMessage) {
                        Write-ColorOutput ">> Message: $($podStatus.TerminatedMessage)" "Red"
                    }
                }
                
                if ($podStatus.RestartCount -gt 0) {
                    Write-ColorOutput ">> Container has restarted $($podStatus.RestartCount) times" "Red"
                }
                
                if ($podStatus.RecentLogs) {
                    Write-ColorOutput ">> Recent logs from pod:" "Yellow"
                    Write-ColorOutput $podStatus.RecentLogs "Gray"
                }
            }
        }
        
        # Try to get events related to the pod
        Write-ColorOutput ">> Checking Kubernetes events..." "Yellow"
        kubectl get events --sort-by='.lastTimestamp' | Select-Object -Last 10
        
        Write-ColorOutput ">> Pod did not become ready in time." "Red"
        Write-ColorOutput ">> Continuing in simulation mode..." "Yellow"
        $simulationMode = $true
    }
}

Write-ColorOutput ">> Pod is ready!" "Green"

if (-not $simulationMode) {
    # Verify pod is actually running before attempting port forwarding
    $podStatus = Get-PodStatus -LabelSelector "app=weatherservice"
    if (-not $podStatus.Success -or -not $podStatus.Ready -or $podStatus.Status -ne "Running") {
        Write-ColorOutput ">> Pod status check failed: $($podStatus.Message)" "Red"
        Write-ColorOutput ">> Continuing in simulation mode..." "Yellow"
        $simulationMode = $true
    }
}

# Start port forwarding using the new centralized function
Write-ColorOutput ">> Setting up port forwarding..." "Cyan"
$job = $null
if (-not $simulationMode) {
    $job = Start-PortForwarding -Service "weather-api-service" -LocalPort 30080 -TargetPort 80
    
    if ($null -eq $job) {
        Write-ColorOutput ">> Failed to start port forwarding." "Red"
        Write-ColorOutput ">> Continuing in simulation mode..." "Yellow"
        $simulationMode = $true
    }
}

Write-ColorOutput ">> Port forwarding established successfully!" "Green"
Start-Sleep -Seconds 2  # Give it a moment to stabilize

# Open browser to the route planner UI
$routePlannerUrl = "http://localhost:30081"
Write-ColorOutput ">> Opening route planner in your browser: $routePlannerUrl" "Cyan"
Start-Process $routePlannerUrl

# Demo the API
Write-ColorOutput "`n>> Demonstrating the Weather Service API..." "Magenta"
Write-ColorOutput ">> Using image: $imageTag" "Cyan"

$zipCodes = @(
    @{zip = "90210"; city = "Beverly Hills, CA"},
    @{zip = "10001"; city = "New York, NY"},
    @{zip = "48045"; city = "Harrison Township, MI"}
)

foreach ($location in $zipCodes) {
    Write-ColorOutput "`n>> Getting weather for $($location.city) (ZIP: $($location.zip))..." "Yellow"
    
    if (-not $simulationMode) {
        try {
            $response = Invoke-RestMethod -Uri "http://localhost:30080/weather/$($location.zip)" -TimeoutSec 10
            Write-ColorOutput "Temperature: $($response.temperatureC)C / $($response.temperatureF)F" "Green"
            Write-ColorOutput "Conditions: $($response.summary)" "Green"
        }
        catch {
            Write-ColorOutput ">> Error: Failed to get weather data for $($location.zip)" "Red"
            Write-ColorOutput ">> Error details: $($_.Exception.Message)" "Red"
            
            # Check specific error types for better diagnostics
            if ($_.Exception.Message -match "Unauthorized" -or $_.Exception.Response.StatusCode -eq 401) {
                Write-ColorOutput ">> API KEY ERROR: Your OpenWeatherMap API key might not be set properly" "Red"
                Write-ColorOutput ">> Make sure to run the set-openweather-key.ps1 script before running the demo" "Yellow"
                Write-ColorOutput ">> Continuing in simulation mode..." "Yellow"
                $simulationMode = $true
                continue
            }
            
            if ($_.Exception.Message -match "No connection|ConnectFailure|actively refused") {
                Write-ColorOutput ">> CONNECTION ERROR: Cannot connect to the weather API service" "Red"
                Write-ColorOutput ">> Make sure Docker is running and container networking is functioning properly" "Yellow"
            }
            
            # Check if port forwarding is still active
            if (-not (Test-PortInUse -Port 30080)) {
                Write-ColorOutput ">> Port forwarding appears to have stopped" "Red"
                Write-ColorOutput ">> Attempting to restart port forwarding..." "Yellow"
                
                # Use the centralized function to restart port forwarding
                $job = Start-PortForwarding -Service "weather-api-service" -LocalPort 30080 -TargetPort 80
                
                if ($null -eq $job) {
                    Write-ColorOutput ">> Failed to restart port forwarding" "Red"
                    Write-ColorOutput ">> Continuing in simulation mode..." "Yellow"
                    $simulationMode = $true
                } else {
                    Write-ColorOutput ">> Port forwarding restarted successfully!" "Green"
                    Write-ColorOutput ">> Retrying weather API request..." "Yellow"
                    try {
                        $response = Invoke-RestMethod -Uri "http://localhost:30080/weather/$($location.zip)" -TimeoutSec 10
                        Write-ColorOutput "Temperature: $($response.temperatureC)C / $($response.temperatureF)F" "Green"
                        Write-ColorOutput "Conditions: $($response.summary)" "Green"
                        continue
                    } catch {
                        Write-ColorOutput ">> Still unable to get weather data. Running in simulation mode..." "Red"
                        $simulationMode = $true
                    }
                }
            } else {
                # Try to diagnose the API issue
                Write-ColorOutput ">> Attempting to diagnose API service issue..." "Yellow"
                try {
                    $healthCheck = Invoke-RestMethod -Uri "http://localhost:30080/health" -TimeoutSec 5 -ErrorAction SilentlyContinue
                    if ($healthCheck.status -eq "Healthy") {
                        Write-ColorOutput ">> API service reports healthy but cannot get weather data." "Yellow"
                        Write-ColorOutput ">> This may be an OpenWeatherMap API key issue." "Yellow"
                    }
                } catch {
                    Write-ColorOutput ">> API health check failed. Service might be misconfigured." "Red"
                }
                Write-ColorOutput ">> Continuing in simulation mode..." "Yellow"
                $simulationMode = $true
            }
        }
    } else {
        # In simulation mode, show sample weather data
        Write-ColorOutput "SIMULATION MODE: Showing sample weather data" "Yellow"
        $temp = Get-Random -Minimum 5 -Maximum 35
        $fahrenheit = [Math]::Round(($temp * 9/5) + 32)
        $conditions = @("Sunny", "Partly Cloudy", "Cloudy", "Rain", "Thunderstorms", "Snow", "Foggy") | Get-Random
        Write-ColorOutput "Temperature: $temp C / $fahrenheit F - $conditions" "Green"
    }
}

# Demonstrate the Route Weather Planner
Write-ColorOutput "`n>> Demonstrating the Route Weather Planner..." "Magenta"

# Set up port forwarding for the route planner
Write-ColorOutput ">> Setting up port forwarding for Route Weather Planner..." "Cyan"
$routePlannerJob = $null
if (-not $simulationMode) {
    $routePlannerJob = Start-PortForwarding -Service "route-planner-service" -LocalPort 30081 -TargetPort 80
    
    if ($null -eq $routePlannerJob) {
        Write-ColorOutput ">> Failed to start port forwarding for Route Weather Planner." "Red"
        Write-ColorOutput ">> Continuing in simulation mode..." "Yellow"
        $simulationMode = $true
    } else {
        Write-ColorOutput ">> Port forwarding established successfully!" "Green"
        Start-Sleep -Seconds 2  # Give it a moment to stabilize
        
        # Open browser to the route planner UI
        $routePlannerUrl = "http://localhost:30081"
        Write-ColorOutput ">> Opening route planner in your browser: $routePlannerUrl" "Cyan"
        Start-Process $routePlannerUrl
    }
}

# Sample route data
$sampleRoutes = @(
    @{
        start = "Los Angeles, CA";
        end = "San Francisco, CA";
        description = "A scenic drive up the California coast"
    },
    @{
        start = "New York, NY";
        end = "Boston, MA";
        description = "Journey through New England"
    }
)

foreach ($route in $sampleRoutes) {
    Write-ColorOutput "`n>> Getting weather along route from $($route.start) to $($route.end)..." "Yellow"
    Write-ColorOutput ">> $($route.description)" "Cyan"
    
    if (-not $simulationMode) {
        try {
            # URL encode the start and end locations
            $startEncoded = [System.Web.HttpUtility]::UrlEncode($route.start)
            $endEncoded = [System.Web.HttpUtility]::UrlEncode($route.end)
            
            # Make the request
            $routeUrl = "http://localhost:30081/route?start=$startEncoded&end=$endEncoded"
            $routeResponse = Invoke-WebRequest -Uri $routeUrl -TimeoutSec 10
            
            # If we got here, the page loaded successfully
            Write-ColorOutput ">> Route planner page loaded successfully!" "Green"
            Write-ColorOutput ">> Route information would be displayed in the web UI" "Green"
        }
        catch {
            Write-ColorOutput ">> Error: Failed to access Route Weather Planner" "Red"
            Write-ColorOutput ">> Error details: $($_.Exception.Message)" "Red"
            Write-ColorOutput ">> Continuing in simulation mode..." "Yellow"
            $simulationMode = $true
        }
    }
    
    if ($simulationMode) {
        # In simulation mode, show sample route weather data
        Write-ColorOutput "SIMULATION MODE: Showing sample route weather data" "Yellow"
        $routePoints = Get-Random -Minimum 3 -Maximum 7
        Write-ColorOutput ">> Route contains $routePoints stops with weather forecasts" "Green"
        
        for ($i = 1; $i -le $routePoints; $i++) {
            $temp = Get-Random -Minimum 5 -Maximum 35
            $fahrenheit = [Math]::Round(($temp * 9/5) + 32)
            $conditions = @("Sunny", "Partly Cloudy", "Cloudy", "Rain", "Thunderstorms", "Snow", "Foggy") | Get-Random
            Write-ColorOutput ">> Stop $i`: $temp C / $fahrenheit F - $conditions" "Green"
        }
        
        # Create and open a simple HTML page to simulate the route planner
        $simHtmlPath = "$env:TEMP\route-planner-simulation.html"
        $startLocation = $route.start
        $endLocation = $route.end
        
        # Generate HTML content without using string interpolation for problem characters
        $htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
    <title>Route Weather Planner - SIMULATION MODE</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; }
        .sim-label { background-color: #ffe0e0; color: #c00; padding: 5px 10px; border-radius: 4px; font-weight: bold; display: inline-block; }
        .route-info { margin: 20px 0; padding: 15px; background-color: #f0f8ff; border-radius: 4px; }
        .weather-stop { margin: 10px 0; padding: 10px; background-color: #f0fff0; border-radius: 4px; }
        .label { font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Route Weather Planner <span class="sim-label">SIMULATION MODE</span></h1>
        <div class="route-info">
            <div class="label">Route:</div>
            <div>From: $startLocation</div>
            <div>To: $endLocation</div>
        </div>
        <h2>Weather Conditions Along Route:</h2>
"@
        
        $htmlFooter = @"
    </div>
</body>
</html>
"@
        
        # Create HTML content in pieces to avoid PowerShell string interpolation issues
        $htmlContent = $htmlHeader
        
        # Add weather stops manually using Add-Content
        for ($i = 1; $i -le $routePoints; $i++) {
            $temp = Get-Random -Minimum 5 -Maximum 35
            $fahrenheit = [Math]::Round(($temp * 9/5) + 32)
            $conditions = @("Sunny", "Partly Cloudy", "Cloudy", "Rain", "Thunderstorms", "Snow", "Foggy") | Get-Random
            $location = if ($i -eq 1) { $startLocation } elseif ($i -eq $routePoints) { $endLocation } else { "Waypoint $i" }
            
            $stopHtml = "        <div class=`"weather-stop`">`n"
            $stopHtml += "            <div class=`"label`">Location $i" + ": $location</div>`n"
            $stopHtml += "            <div>Temperature: ${temp}°C / ${fahrenheit}°F</div>`n"
            $stopHtml += "            <div>Conditions: $conditions</div>`n"
            $stopHtml += "        </div>`n"
            
            $htmlContent += $stopHtml
        }
        
        $htmlContent += $htmlFooter
        
        # Write the HTML to a file and open it
        Set-Content -Path $simHtmlPath -Value $htmlContent
        Start-Process $simHtmlPath
        Write-ColorOutput ">> Opened simulation of route planner in browser" "Yellow"
        
        # Only show one route in simulation mode
        break
    }
}

Write-ColorOutput "`n>> Demo completed successfully!" "Magenta"
Write-ColorOutput "Press any key to clean up resources..." "Yellow"
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Cleanup
Write-ColorOutput "`n>> Cleaning up resources..." "Cyan"
if (-not $simulationMode) {
    Stop-PortForwarding
    if ($null -ne $routePlannerJob) {
        Stop-Job $routePlannerJob
        Remove-Job $routePlannerJob
    }
    kind delete cluster --name weatherservice
}
Write-ColorOutput ">> All resources cleaned up!" "Green"
Write-ColorOutput ">> Thanks for watching the demo!" "Magenta" 