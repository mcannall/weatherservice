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

function Show-CICDPipeline {
    Write-ColorOutput "`n🔄 CI/CD Pipeline Overview" "Magenta"
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
            command = "docker build -t ghcr.io/mcannall/weatherservice:latest"
        },
        @{
            title = "5. Push to GitHub Packages"
            description = "Pushes image to GitHub Container Registry"
            command = "docker push ghcr.io/mcannall/weatherservice:latest"
        },
        @{
            title = "6. Deploy to Kubernetes"
            description = "Updates Kubernetes deployment with new image"
            command = "kubectl set image deployment/api api=ghcr.io/mcannall/weatherservice:latest"
        }
    )

    foreach ($step in $steps) {
        Write-ColorOutput "`n$($step.title)" "Yellow"
        Write-ColorOutput $step.description "White"
        Write-ColorOutput "Command: $($step.command)" "Cyan"
        Start-Sleep -Seconds 2
    }
}

# Check prerequisites
Write-ColorOutput "🔍 Checking prerequisites..." "Cyan"
$prerequisites = @("docker", "kind", "kubectl")
$missing = @()

foreach ($tool in $prerequisites) {
    if (-not (Test-CommandExists $tool)) {
        $missing += $tool
    }
}

if ($missing.Count -gt 0) {
    Write-ColorOutput "❌ Missing required tools: $($missing -join ', ')" "Red"
    Write-ColorOutput "Please install the missing tools and try again." "Red"
    exit 1
}

Write-ColorOutput "✅ All prerequisites found!" "Green"

# Show CI/CD Pipeline
Show-CICDPipeline

Write-ColorOutput "`n🚀 Starting local deployment demo..." "Magenta"
Write-ColorOutput "This will demonstrate how the service runs in Kubernetes" "Magenta"
Write-ColorOutput "Press any key to continue..." "Yellow"
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Clean up any existing resources
Write-ColorOutput "🧹 Cleaning up any existing resources..." "Yellow"
kind delete cluster --name weatherservice 2>$null
Write-ColorOutput "✅ Cleanup complete!" "Green"

# Create Kind cluster
Write-ColorOutput "🚀 Creating Kubernetes cluster..." "Cyan"
kind create cluster --name weatherservice
Write-ColorOutput "✅ Cluster created!" "Green"

# Build and load the Docker image
Write-ColorOutput "🏗️ Building Docker image..." "Cyan"
docker build -t ghcr.io/mcannall/weatherservice:latest ./api
Write-ColorOutput "📦 Loading image into Kind cluster..." "Cyan"
kind load docker-image ghcr.io/mcannall/weatherservice:latest --name weatherservice
Write-ColorOutput "✅ Image loaded!" "Green"

# Create Kubernetes resources
Write-ColorOutput "🔧 Creating Kubernetes resources..." "Cyan"
kubectl create secret generic weatherservice-secrets --from-literal=OPENWEATHERMAP_API_KEY=3ba1f600644f4b4c4290d0a97a0c3878
kubectl apply -f k8s/
Write-ColorOutput "✅ Resources created!" "Green"

# Wait for pod to be ready
Write-ColorOutput "⏳ Waiting for pod to be ready..." "Cyan"
kubectl wait --for=condition=ready pod -l app=weatherservice --timeout=60s
Write-ColorOutput "✅ Pod is ready!" "Green"

# Start port forwarding in background
Write-ColorOutput "🔌 Starting port forwarding..." "Cyan"
$job = Start-Job -ScriptBlock {
    kubectl port-forward service/api 30080:80
}
Start-Sleep -Seconds 2
Write-ColorOutput "✅ Port forwarding started!" "Green"

# Demo the API
Write-ColorOutput "`n📡 Demonstrating the Weather Service API..." "Magenta"

$zipCodes = @(
    @{zip = "90210"; city = "Beverly Hills, CA"},
    @{zip = "10001"; city = "New York, NY"},
    @{zip = "48045"; city = "Harrison Township, MI"}
)

foreach ($location in $zipCodes) {
    Write-ColorOutput "`n🌍 Getting weather for $($location.city) (ZIP: $($location.zip))..." "Yellow"
    $response = Invoke-RestMethod -Uri "http://localhost:30080/weather/$($location.zip)"
    Write-ColorOutput "Temperature: $($response.temperatureC)°C / $($response.temperatureF)°F" "Green"
    Write-ColorOutput "Conditions: $($response.summary)" "Green"
}

Write-ColorOutput "`n🎉 Demo completed successfully!" "Magenta"
Write-ColorOutput "Press any key to clean up resources..." "Yellow"
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Cleanup
Write-ColorOutput "`n🧹 Cleaning up resources..." "Cyan"
Stop-Job $job
Remove-Job $job
kind delete cluster --name weatherservice
Write-ColorOutput "✅ All resources cleaned up!" "Green"
Write-ColorOutput "👋 Thanks for watching the demo!" "Magenta" 