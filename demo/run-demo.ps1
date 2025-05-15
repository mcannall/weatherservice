#!/usr/bin/env pwsh

# Weather Service Demo Runner Script
Write-Host "Weather Service Demo Runner" -ForegroundColor Cyan
Write-Host "===========================" -ForegroundColor Cyan
Write-Host "This script will run set-openweather-key.ps1 first to set up your API key,"
Write-Host "then run demo.ps1 in the same PowerShell session."
Write-Host ""
Write-Host "Press Ctrl+C to cancel or Enter to continue..." -ForegroundColor Yellow
$null = Read-Host

# Set up project root directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir  # Go up one level from script directory

# Make sure we have the OpenWeatherMap API key
if (-not $env:OPENWEATHERMAP_API_KEY) {
    Write-Host "Error: OPENWEATHERMAP_API_KEY environment variable is not set." -ForegroundColor Red
    Write-Host "Please set it first by running './demo/set-openweather-key.ps1'" -ForegroundColor Yellow
    exit 1
}

# Check for the .env file for Google Maps API key
$envFile = "$projectRoot/route-weather-planner/.env"
if (-not (Test-Path $envFile)) {
    Write-Host "Error: $envFile does not exist." -ForegroundColor Red
    Write-Host "Please create it from .env.template and add your Google Maps API key." -ForegroundColor Yellow
    exit 1
}

# Build Docker images
Write-Host "Building the route-weather-planner Docker image..." -ForegroundColor Cyan
docker build -t ghcr.io/mcannall/weatherservice/route-weather-planner:local-demo "$projectRoot/route-weather-planner"

# Run the demo
Write-Host "Starting the demo script..." -ForegroundColor Green
& "$scriptDir/demo.ps1" 