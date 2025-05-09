# Weather Service Demo

This demo showcases the Weather Service running in Kubernetes using Kind (Kubernetes in Docker) and demonstrates the complete CI/CD pipeline.

## Prerequisites

The following tools must be installed:
- Docker
- Kind (Kubernetes in Docker)
- kubectl (Kubernetes command-line tool)

## Running the Demo

1. Open PowerShell
2. Navigate to the repository root directory
3. Run the demo script:
   ```powershell
   ./demo/demo.ps1
   ```

## What the Demo Shows

### CI/CD Pipeline Overview
The demo first shows the complete CI/CD pipeline:
1. Code Change: Developer commits code to GitHub
2. GitHub Actions Trigger: Workflow starts automatically
3. Build & Test: .NET application build and test
4. Docker Build: Creates container image
5. Push to GitHub Packages: Stores image in GitHub Container Registry
6. Deploy to Kubernetes: Updates deployment with new image

### Local Deployment Demo
Then demonstrates the local deployment:
1. Check for required tools
2. Create a local Kubernetes cluster using Kind
3. Build and load the Weather Service Docker image
4. Deploy the service to Kubernetes
5. Demonstrate the API by fetching weather for different cities:
   - Beverly Hills, CA (90210)
   - New York, NY (10001)
   - Harrison Township, MI (48045)
6. Clean up all resources when finished

## Features

- 🔄 Complete CI/CD pipeline visualization
- 🔍 Prerequisite checking
- 🎨 Colorful output
- 🔄 Automatic cleanup
- 🌈 Emoji-enhanced progress indicators
- ⏱️ Proper timing and pauses for readability
- 🧹 Graceful cleanup on completion

## Notes

- The demo takes approximately 5-7 minutes to run
- All resources are automatically cleaned up when the demo completes
- Press any key at the end to clean up resources
- The CI/CD pipeline shown is the same one used in production 