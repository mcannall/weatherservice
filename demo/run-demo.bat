@echo off
ECHO Weather Service Demo Runner
ECHO ===========================
ECHO This script will run set-openweather-key.ps1 first to set up your API key,
ECHO then run demo.ps1 in the same PowerShell session.
ECHO.
ECHO Press Ctrl+C to cancel or any other key to continue...
PAUSE > nul

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& {cd '%~dp0'; . .\set-openweather-key.ps1; if ($env:OPENWEATHERMAP_API_KEY) { . .\demo.ps1 } else { Write-Host 'API key not set, demo aborted.' -ForegroundColor Red }}" 