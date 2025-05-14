# PowerShell script to check for OKE clusters in Oracle Cloud
# Author: AI Assistant
# Date: 2025-05-14

# Set up colors for output
$RED = [ConsoleColor]::Red
$GREEN = [ConsoleColor]::Green
$YELLOW = [ConsoleColor]::Yellow
$BLUE = [ConsoleColor]::Cyan

function Write-ColoredOutput {
    param (
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    Write-Host $Message -ForegroundColor $Color
}

Write-ColoredOutput "=============================================" $BLUE
Write-ColoredOutput "     Oracle Cloud Kubernetes Cluster Check    " $BLUE
Write-ColoredOutput "=============================================" $BLUE

# Check if OCI CLI is installed
if (-not (Get-Command "oci" -ErrorAction SilentlyContinue)) {
    Write-ColoredOutput "Error: OCI CLI is not installed." $RED
    Write-Host "Please install the Oracle Cloud CLI first: https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm"
    exit 1
}

# Check if OCI CLI is configured
if (-not (Test-Path "~/.oci/config")) {
    Write-ColoredOutput "Error: OCI CLI is not configured." $RED
    Write-Host "Please run 'oci setup config' to configure the CLI first."
    exit 1
}

# Default region
$REGION = "us-chicago-1"

Write-ColoredOutput "Using region: $REGION" $BLUE

# Get tenancy OCID from OCI config
$tenancyLine = Get-Content "~/.oci/config" | Where-Object { $_ -match "^tenancy=" }
if (-not $tenancyLine) {
    Write-ColoredOutput "Error: Could not find tenancy OCID in OCI config." $RED
    exit 1
}
$TENANCY_OCID = $tenancyLine.Split("=")[1].Trim()

Write-ColoredOutput "Using tenancy: $TENANCY_OCID" $BLUE

# List all compartments
Write-ColoredOutput "`nListing compartments..." $BLUE
$compartmentsJSON = oci iam compartment list --compartment-id "$TENANCY_OCID" --all --query "data[*].id" --raw-output --region "$REGION"
$COMPARTMENTS = $compartmentsJSON -split '\r?\n' | Where-Object { $_ }
Write-ColoredOutput "Root compartment ID: $TENANCY_OCID" $GREEN

# Function to list clusters in a compartment
function List-ClustersInCompartment {
    param (
        [string]$compartmentId,
        [string]$compartmentName
    )
    
    Write-ColoredOutput "`nChecking for clusters in compartment: $compartmentName" $BLUE
    
    # List clusters in the compartment
    try {
        $clusterListOutput = oci ce cluster list --compartment-id "$compartmentId" --region "$REGION" 2>&1
        $clusterListJSON = $clusterListOutput | ConvertFrom-Json -ErrorAction SilentlyContinue
    }
    catch {
        Write-ColoredOutput "Unable to list clusters in this compartment (possibly no permissions)" $YELLOW
        return
    }
    
    if (-not $clusterListJSON -or -not $clusterListJSON.data -or $clusterListJSON.data.Count -eq 0) {
        Write-ColoredOutput "No Kubernetes clusters found in this compartment" $YELLOW
        return
    }
    
    # Print cluster information
    Write-ColoredOutput "Found clusters in $compartmentName`:" $GREEN
    Write-ColoredOutput "-----------------------------------------------" $BLUE
    Write-ColoredOutput "CLUSTER ID                                 | NAME                | STATE" $BLUE
    Write-ColoredOutput "-----------------------------------------------" $BLUE
    
    foreach ($cluster in $clusterListJSON.data) {
        Write-Host "$($cluster.id) | $($cluster.name) | $($cluster.'lifecycle-state')"
    }
    
    Write-ColoredOutput "-----------------------------------------------" $BLUE
}

# Check for clusters in the root compartment
List-ClustersInCompartment -compartmentId $TENANCY_OCID -compartmentName "Root Compartment"

# Check for clusters in sub-compartments
foreach ($compartmentId in $COMPARTMENTS) {
    try {
        $compartmentInfo = oci iam compartment get --compartment-id "$compartmentId" --query "data.name" --raw-output --region "$REGION" 2>&1
        if ($LASTEXITCODE -eq 0 -and $compartmentInfo) {
            List-ClustersInCompartment -compartmentId $compartmentId -compartmentName $compartmentInfo
        }
    }
    catch {
        # Skip compartments we can't access
    }
}

Write-ColoredOutput "`n=============================================" $BLUE
Write-ColoredOutput "               Summary                       " $BLUE
Write-ColoredOutput "=============================================" $BLUE

Write-ColoredOutput "`nTo use a cluster ID in your GitHub Actions workflow:" $GREEN
Write-Host "1. Copy the full Cluster ID from above"
Write-Host "2. Run the GitHub workflow with this ID provided in the input parameters"
Write-Host "3. To check cluster details use: " -NoNewline
Write-ColoredOutput "oci ce cluster get --cluster-id <CLUSTER_ID> --region $REGION" $YELLOW

Write-ColoredOutput "`nIf no clusters are listed, you'll need to create a Kubernetes cluster first:" $YELLOW
Write-Host "1. Go to your Oracle Cloud console: https://cloud.oracle.com"
Write-Host "2. Navigate to Developer Services > Kubernetes Clusters (OKE)"
Write-Host "3. Click 'Create Cluster' and follow the wizard (Quick Create is recommended for new users)"
Write-Host "4. After creation (5-15 minutes), run this script again to get the cluster ID"

Write-ColoredOutput "`n=============================================" $BLUE 