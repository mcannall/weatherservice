#!/usr/bin/env pwsh

# Weather Service Demo Runner Script
Write-Host "Weather Service Demo Runner" -ForegroundColor Cyan
Write-Host "===========================" -ForegroundColor Cyan
Write-Host "This script will check your environment, build Docker images, and run the demo" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press Ctrl+C to cancel or Enter to continue..." -ForegroundColor Yellow
$null = Read-Host

# Set up project root directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir  # Go up one level from script directory

# Function to check prerequisites
function Test-Prerequisites {
    Write-Host "`nChecking prerequisites..." -ForegroundColor Cyan
    
    # Check Docker is running
    try {
        $dockerInfo = docker info 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Docker is not running or not accessible" -ForegroundColor Red
            Write-Host "   Please make sure Docker Desktop is running before continuing" -ForegroundColor Yellow
            return $false
        }
        Write-Host "✅ Docker is running" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Docker command failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   Please make sure Docker is installed and running" -ForegroundColor Yellow
        return $false
    }
    
    # Check for Kubernetes
    try {
        $k8sVersion = kubectl version --client --short 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ kubectl not found or not accessible" -ForegroundColor Red
            Write-Host "   Please make sure Kubernetes CLI is installed" -ForegroundColor Yellow
            return $false
        }
        Write-Host "✅ kubectl is installed: $k8sVersion" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ kubectl command failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   Please make sure kubectl is installed" -ForegroundColor Yellow
        return $false
    }
    
    # Check for required API keys
    if (-not $env:OPENWEATHERMAP_API_KEY) {
        Write-Host "❌ OPENWEATHERMAP_API_KEY environment variable is not set" -ForegroundColor Red
        
        # Try to offer help
        $apiKeyScript = "$scriptDir\set-openweather-key.ps1"
        if (Test-Path $apiKeyScript) {
            Write-Host "`nWould you like to set your OpenWeatherMap API key now? (y/n)" -ForegroundColor Yellow
            $response = Read-Host
            if ($response.ToLower() -eq 'y') {
                & $apiKeyScript
                if (-not $env:OPENWEATHERMAP_API_KEY) {
                    Write-Host "❌ Failed to set OpenWeatherMap API key" -ForegroundColor Red
                    return $false
                }
                Write-Host "✅ OpenWeatherMap API key set successfully" -ForegroundColor Green
            } else {
                Write-Host "You can set it later by running './demo/set-openweather-key.ps1'" -ForegroundColor Yellow
                Write-Host "The demo will run in simulation mode without real weather data" -ForegroundColor Yellow
            }
        } else {
            Write-Host "Please set it by running './demo/set-openweather-key.ps1'" -ForegroundColor Yellow
            Write-Host "The demo will run in simulation mode without real weather data" -ForegroundColor Yellow
        }
    } else {
        Write-Host "✅ OpenWeatherMap API key is set" -ForegroundColor Green
    }
    
    # Check for Google Maps API key
    $envFile = "$projectRoot/route-weather-planner/.env"
    if (Test-Path $envFile) {
        $envContent = Get-Content $envFile -Raw
        if ($envContent -match "GOOGLE_MAPS_API_KEY=(.+)") {
            $googleMapsKey = $matches[1].Trim('"').Trim("'")
            if ($googleMapsKey -and $googleMapsKey -ne "your_google_maps_api_key_here") {
                Write-Host "✅ Google Maps API key found in .env file" -ForegroundColor Green
            } else {
                Write-Host "❌ Invalid Google Maps API key in .env file" -ForegroundColor Red
                Write-Host "   Please edit route-weather-planner/.env and add your valid Google Maps API key" -ForegroundColor Yellow
            }
        } else {
            Write-Host "❌ Google Maps API key not found in .env file" -ForegroundColor Red
            Write-Host "   Please edit route-weather-planner/.env and add your Google Maps API key" -ForegroundColor Yellow
        }
    } else {
        Write-Host "❌ .env file not found at: $envFile" -ForegroundColor Red
        Write-Host "   Creating .env file from template..." -ForegroundColor Yellow
        
        $templateFile = "$projectRoot/route-weather-planner/.env.template"
        if (Test-Path $templateFile) {
            Copy-Item $templateFile $envFile
            Write-Host "✅ Created .env file from template" -ForegroundColor Green
            Write-Host "   Please edit $envFile and add your Google Maps API key" -ForegroundColor Yellow
        } else {
            Write-Host "❌ .env.template file not found" -ForegroundColor Red
            Write-Host "   Please create $envFile manually with your Google Maps API key" -ForegroundColor Yellow
        }
    }
    
    return $true
}

# Run prerequisites check
$prereqOk = Test-Prerequisites
if (-not $prereqOk) {
    Write-Host "`nSome prerequisites are not met. Would you like to continue anyway? (y/n)" -ForegroundColor Yellow
    $continue = Read-Host
    if ($continue.ToLower() -ne "y") {
        Write-Host "Exiting demo setup. Please resolve the issues and try again." -ForegroundColor Red
        exit 1
    }
    Write-Host "Continuing with setup. Some features may not work correctly." -ForegroundColor Yellow
}

# Build Docker images
Write-Host "`nBuilding Docker images..." -ForegroundColor Cyan

# Build Weather API image
Write-Host "Building the Weather API Docker image..." -ForegroundColor Cyan
$apiResult = docker build -t ghcr.io/mcannall/weatherservice:local-demo "$projectRoot/api" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to build Weather API image:" -ForegroundColor Red
    Write-Host $apiResult -ForegroundColor Red
    Write-Host "The demo may still work in simulation mode" -ForegroundColor Yellow
} else {
    Write-Host "✅ Weather API image built successfully" -ForegroundColor Green
}

# Build Route Planner image
Write-Host "Building the Route Weather Planner Docker image..." -ForegroundColor Cyan
$routeResult = docker build -t ghcr.io/mcannall/weatherservice/route-weather-planner:local-demo "$projectRoot/route-weather-planner" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to build Route Weather Planner image:" -ForegroundColor Red
    Write-Host $routeResult -ForegroundColor Red
    Write-Host "The demo may still work in simulation mode" -ForegroundColor Yellow
} else {
    Write-Host "✅ Route Weather Planner image built successfully" -ForegroundColor Green
}

# Run the demo
Write-Host "`nStarting the demo script..." -ForegroundColor Green
& "$scriptDir/demo.ps1" 