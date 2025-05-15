# API Key Security Guide

This document provides guidance on properly handling API keys and sensitive information in the Weather Service project.

## Current Security Status

1. **✅ API Key in `.gitignore`**: 
   - `api/appsettings.json` is properly listed in `.gitignore` to prevent future commits

2. **✅ Local File Retained**:
   - The `api/appsettings.json` file has been updated with a placeholder and remains available locally  

3. **❌ Environment Variable Scripts**:
   - Scripts to securely set API keys need to be recreated (previously created scripts have been removed/deleted)

4. **🔴 Historical Commit Issue**:
   - The file was previously committed with actual API keys before being added to `.gitignore`
   - **Action needed**: Historical commits need to be cleaned

## Recommended Steps to Remove Sensitive Data from Git History

To completely remove sensitive API keys from your Git history, follow these steps:

### Option 1: Using BFG Repo-Cleaner (Recommended)

The BFG is a simpler, faster alternative to `git filter-branch` specifically designed for removing unwanted files from Git history.

1. Download the BFG Jar file from https://rtyley.github.io/bfg-repo-cleaner/
2. Create a backup of your repository
3. Run these commands from your repository root:

```bash
# Clone a fresh copy of your repo (mirror)
git clone --mirror https://github.com/YOUR-USERNAME/weatherservice.git repo.git
cd repo.git

# Run BFG to remove the file from history
java -jar bfg.jar --delete-files api/appsettings.json

# Clean and update the repository
git reflog expire --expire=now --all && git gc --prune=now --aggressive

# Push the changes to GitHub
git push

# Return to your repository and pull the changes
cd ..
git pull
```

### Option 2: Using git filter-branch

If you don't have Java installed or prefer the native Git approach:

```bash
# Make a backup of your repository first!

# Remove the file from all commits
git filter-branch --force --index-filter \
"git rm --cached --ignore-unmatch api/appsettings.json" \
--prune-empty --tag-name-filter cat -- --all

# Force garbage collection
git for-each-ref --format="delete %(refname)" refs/original | git update-ref --stdin
git reflog expire --expire=now --all
git gc --prune=now --aggressive

# Push the changes to remote with force
git push origin --force --all
git push origin --force --tags
```

### Option 3: GitHub's Secret Scanning

GitHub has a feature called "secret scanning" that can detect accidentally committed API keys.
If you're using GitHub, you should also:

1. Go to your repository on GitHub
2. Navigate to "Settings" > "Security" > "Secret scanning"
3. Make sure it's enabled and review any alerts

## Best Practices for API Key Management

1. **Never commit API keys to source control**
   - Use environment variables
   - Use `.env` files that are listed in `.gitignore`

2. **Use template files without real keys**
   - Include `.env.template` or `appsettings.template.json` in the repo
   - Document where to obtain API keys and how to configure them

3. **Use environment-specific configuration**
   - Development: Local `.env` files
   - CI/CD: Repository secrets or secure vault services
   - Production: Environment variables or secure vault services

4. **Rotate compromised keys**
   - If a key has been exposed in Git history, consider it compromised
   - Generate new keys and invalidate old ones

## Local Configuration Setup

For the Weather Service project, developers need to:

1. Copy `api/appsettings.template.json` to `api/appsettings.json`
2. Add their OpenWeatherMap API key to the copied file
3. Copy `route-weather-planner/.env.template` to `route-weather-planner/.env`
4. Add their Google Maps API key to the copied `.env` file

## Recommended Demo Environment Setup

To run the demo safely, you should create a script that:

1. Securely prompts for the OpenWeatherMap API key
2. Sets it as an environment variable only for the current session
3. Does not store the key in any file that could be committed to Git

Example PowerShell script (should be created in `demo/set-openweather-key.ps1`):

```powershell
# Script to securely set OpenWeatherMap API key as environment variable
Write-Host "Setting OpenWeatherMap API key as environment variable" -ForegroundColor Cyan
Write-Host "This will only affect the current PowerShell session" -ForegroundColor Yellow

# Prompt for API key securely
$apiKey = Read-Host "Enter your OpenWeatherMap API key"

# Set environment variable
$env:OPENWEATHERMAP_API_KEY = $apiKey

Write-Host "API key set successfully!" -ForegroundColor Green
Write-Host "You can now run demo.ps1 which will use this environment variable" -ForegroundColor Green
```

Then modify `demo.ps1` to always use this environment variable instead of hardcoded values. 