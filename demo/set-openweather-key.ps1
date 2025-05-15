#!/usr/bin/env pwsh

# Script to securely set OpenWeatherMap API key as environment variable
# Run this script before running demo.ps1

function Write-ColorOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [string]$ForegroundColor = "White"
    )
    Write-Host $Message -ForegroundColor $ForegroundColor
}

# ASCII art for script header
Write-Host @"
 _____                 _    _            _   _                       
|  _  |               | |  | |          | | | |                      
| | | |_ __   ___ _ __| |  | | ___  __ _| |_| |__   ___ _ __         
| | | | '_ \ / _ \ '_ \ |/\| |/ _ \/ _\` | __| '_ \ / _ \ '__|       
\ \_/ / |_) |  __/ | | \  /\  /  __/ (_| | |_| | | |  __/ |          
 \___/| .__/ \___|_| |_|\/  \/ \___|\__,_|\__|_| |_|\___|_|          
      | |     _    ___ ___   _  __            ___      _             
      |_|    /_\  | _ \_ _| | |/ /___ _  _   / __| ___| |_ _  _ _ __ 
           / _ \ |  _/| |  | ' </ -_) || | | (__ / -_)  _| || | '_ \
          /_/ \_\|_| |___| |_|\_\___|\_, |  \___\___|\__|\_,_| .__/
                                      |__/                    |_|   
"@ -ForegroundColor Cyan

Write-ColorOutput "`nThis script sets the OpenWeatherMap API key as an environment variable" "Yellow"
Write-ColorOutput "for the current PowerShell session only. The key will not be stored permanently" "Yellow"
Write-ColorOutput "or committed to Git.`n" "Yellow"

# Check if the key is already set
if ($env:OPENWEATHERMAP_API_KEY) {
    Write-ColorOutput "OpenWeatherMap API Key is already set in this session." "Green"
    $masked = "*" * ($env:OPENWEATHERMAP_API_KEY.Length - 4) + $env:OPENWEATHERMAP_API_KEY.Substring($env:OPENWEATHERMAP_API_KEY.Length - 4)
    Write-ColorOutput "Current key value: $masked" "Green"
    $reset = Read-Host "Do you want to change it? (y/n)"
    if ($reset.ToLower() -ne 'y') {
        Write-ColorOutput "`nKeeping existing API key. You can now run demo.ps1" "Green"
        exit 0
    }
}

# Prompt for the API key
Write-ColorOutput "`nEnter your OpenWeatherMap API key:" "Cyan"
Write-ColorOutput "(If you don't have one, get it from https://openweathermap.org/api)" "Gray"
$apiKey = Read-Host

# Validate input
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    Write-ColorOutput "`nERROR: No API key provided. Exiting without setting the environment variable." "Red"
    exit 1
}

# Set the environment variable for the current session
$env:OPENWEATHERMAP_API_KEY = $apiKey

# Verify that it was set
if ($env:OPENWEATHERMAP_API_KEY -eq $apiKey) {
    Write-ColorOutput "`nSUCCESS: OpenWeatherMap API key has been set for this PowerShell session." "Green"
    Write-ColorOutput "This setting will be lost when you close the current PowerShell window." "Yellow"
    Write-ColorOutput "`nYou can now run demo.ps1" "Green"
} else {
    Write-ColorOutput "`nERROR: Failed to set the environment variable." "Red"
    exit 1
}

# Optional: Display reminder about .env file for frontend
$envPath = "route-weather-planner/.env"
if (Test-Path $envPath) {
    Write-ColorOutput "`nNOTE: The frontend .env file exists at $envPath" "Cyan"
    Write-ColorOutput "Make sure it contains your Google Maps API key (GOOGLE_MAPS_API_KEY)" "Cyan"
} else {
    Write-ColorOutput "`nNOTE: Don't forget to create the frontend .env file at $envPath" "Yellow"
    Write-ColorOutput "You can copy route-weather-planner/.env.template and add your Google Maps API key" "Yellow"
} 