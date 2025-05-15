#!/usr/bin/env pwsh

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
    $csproj = Get-Content "api/api.csproj" -Raw
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
    $csproj = Get-Content "api/api.csproj" -Raw
    $csproj = $csproj -replace '<Version>[\d\.]+</Version>', "<Version>$NewVersion</Version>"
    Set-Content -Path "api/api.csproj" -Value $csproj
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
    Stop-PortForwarding

    # Verify port is available
    if (Test-PortInUse -Port $LocalPort) {
        Write-ColorOutput ">> Error: Port $LocalPort is in use" "Red"
        Write-ColorOutput ">> Please ensure no other processes are using port $LocalPort" "Red"
        return $null
    }

    # Start port forwarding in background
    Write-ColorOutput ">> Starting port forwarding..." "Cyan"
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
            Write-ColorOutput ">> Port forwarding started successfully!" "Green"
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
$projectRoot = Get-Location
$env:OPENWEATHERMAP_API_KEY = "your-api-key-here"  # Replace with your actual API key
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
    git add api/api.csproj
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
} else {
    # Option 2: Build locally
    $imageTag = "ghcr.io/mcannall/weatherservice:local-demo"
}

# Clean up any existing resources
Write-ColorOutput ">> Cleaning up any existing resources..." "Yellow"
kind delete cluster --name weatherservice 2>$null
Write-ColorOutput ">> Cleanup complete!" "Green"

# Create Kind cluster
Write-ColorOutput ">> Creating Kubernetes cluster..." "Cyan"
Show-Progress -Activity "Creating cluster" -Status "Initializing..." -PercentComplete 0
kind create cluster --name weatherservice
Show-Progress -Activity "Creating cluster" -Status "Complete" -PercentComplete 100
Write-ColorOutput ">> Cluster created!" "Green"

if ($choice -eq "1") {
    # Pull the image from GitHub Packages
    Write-ColorOutput ">> Pulling image from GitHub Packages..." "Cyan"
    Show-Progress -Activity "Pulling image" -Status "Pulling..." -PercentComplete 0
    docker pull $imageTag
    Show-Progress -Activity "Pulling image" -Status "Complete" -PercentComplete 100
} else {
    # Build the image locally
    Write-ColorOutput ">> Building Docker image locally..." "Cyan"
    Show-Progress -Activity "Building image" -Status "Building..." -PercentComplete 0
    docker build -t $imageTag ./api
    Show-Progress -Activity "Building image" -Status "Complete" -PercentComplete 100
}

Write-ColorOutput ">> Loading image into Kind cluster..." "Cyan"
Show-Progress -Activity "Loading image" -Status "Loading..." -PercentComplete 0
kind load docker-image $imageTag --name weatherservice
Show-Progress -Activity "Loading image" -Status "Complete" -PercentComplete 100
Write-ColorOutput ">> Image loaded!" "Green"

# Create Kubernetes resources
Write-ColorOutput ">> Creating Kubernetes resources..." "Cyan"

# Read Google Maps API key from .env file
$envPath = "route-weather-planner/.env"
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
    OPENWEATHERMAP_API_KEY = "3ba1f600644f4b4c4290d0a97a0c3878"
    GOOGLE_MAPS_API_KEY = $googleMapsApiKey
}
$secretArgs = $secrets.GetEnumerator() | ForEach-Object { "--from-literal=$($_.Key)=$($_.Value)" }
kubectl create secret generic weatherservice-secrets $secretArgs
kubectl apply -f k8s/
Write-ColorOutput ">> Resources created!" "Green"

# Wait for pod to be ready
Write-ColorOutput ">> Waiting for pod to be ready..." "Cyan"
Show-Progress -Activity "Waiting for pod" -Status "Waiting..." -PercentComplete 0

$waitResult = kubectl wait --for=condition=ready pod -l app=weatherservice --timeout=60s 2>&1
$waitSuccess = $LASTEXITCODE -eq 0

Show-Progress -Activity "Waiting for pod" -Status "Complete" -PercentComplete 100

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
    
    Write-ColorOutput ">> Pod did not become ready in time. Cleaning up and exiting..." "Red"
    kind delete cluster --name weatherservice
    exit 1
}

Write-ColorOutput ">> Pod is ready!" "Green"

# Verify pod is actually running before attempting port forwarding
$podStatus = Get-PodStatus -LabelSelector "app=weatherservice"
if (-not $podStatus.Success -or -not $podStatus.Ready -or $podStatus.Status -ne "Running") {
    Write-ColorOutput ">> Pod status check failed: $($podStatus.Message)" "Red"
    Write-ColorOutput ">> Cannot proceed with port forwarding. Cleaning up and exiting..." "Red"
    kind delete cluster --name weatherservice
    exit 1
}

# Start port forwarding using the new centralized function
Write-ColorOutput ">> Setting up port forwarding..." "Cyan"
$job = Start-PortForwarding -Service "api" -LocalPort 30080 -TargetPort 80

if ($null -eq $job) {
    Write-ColorOutput ">> Failed to start port forwarding. Cleaning up and exiting..." "Red"
    kind delete cluster --name weatherservice
    exit 1
}

Write-ColorOutput ">> Port forwarding established successfully!" "Green"

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
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:30080/weather/$($location.zip)" -TimeoutSec 10
        Write-ColorOutput "Temperature: $($response.temperatureC)C / $($response.temperatureF)F" "Green"
        Write-ColorOutput "Conditions: $($response.summary)" "Green"
    }
    catch {
        Write-ColorOutput ">> Error: Failed to get weather data for $($location.zip)" "Red"
        Write-ColorOutput ">> Error details: $($_.Exception.Message)" "Red"
        
        # Check if port forwarding is still active
        if (-not (Test-PortInUse -Port 30080)) {
            Write-ColorOutput ">> Port forwarding appears to have stopped" "Red"
            Write-ColorOutput ">> Attempting to restart port forwarding..." "Yellow"
            
            # Use the centralized function to restart port forwarding
            $job = Start-PortForwarding -Service "api" -LocalPort 30080 -TargetPort 80
            
            if ($null -eq $job) {
                Write-ColorOutput ">> Failed to restart port forwarding" "Red"
                Write-ColorOutput ">> Cleaning up and exiting..." "Red"
                kind delete cluster --name weatherservice
                exit 1
            }
            
            Write-ColorOutput ">> Port forwarding restarted successfully!" "Green"
        }
    }
}

Write-ColorOutput "`n>> Demo completed successfully!" "Magenta"
Write-ColorOutput "Press any key to clean up resources..." "Yellow"
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Cleanup
Write-ColorOutput "`n>> Cleaning up resources..." "Cyan"
Stop-PortForwarding
kind delete cluster --name weatherservice
Write-ColorOutput ">> All resources cleaned up!" "Green"
Write-ColorOutput ">> Thanks for watching the demo!" "Magenta" 