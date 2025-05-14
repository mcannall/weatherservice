#!/bin/bash
# Script to check for OKE clusters in Oracle Cloud
# Author: AI Assistant
# Date: 2025-05-14

# Set up colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}     Oracle Cloud Kubernetes Cluster Check    ${NC}"
echo -e "${BLUE}==============================================${NC}"

# Check if OCI CLI is installed
if ! command -v oci &> /dev/null; then
    echo -e "${RED}Error: OCI CLI is not installed.${NC}"
    echo -e "Please install the Oracle Cloud CLI first: https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm"
    exit 1
fi

# Check if OCI CLI is configured
if [ ! -f ~/.oci/config ]; then
    echo -e "${RED}Error: OCI CLI is not configured.${NC}"
    echo -e "Please run 'oci setup config' to configure the CLI first."
    exit 1
fi

# Default region - can be overridden by command line
REGION="us-chicago-1"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --region)
        REGION="$2"
        shift
        shift
        ;;
        *)
        echo -e "${YELLOW}Unknown option: $1${NC}"
        shift
        ;;
    esac
done

echo -e "${BLUE}Using region: ${REGION}${NC}"

# Get tenancy OCID from OCI config
TENANCY_OCID=$(grep -i "^tenancy" ~/.oci/config | head -1 | cut -d'=' -f2 | tr -d ' ')
if [ -z "$TENANCY_OCID" ]; then
    echo -e "${RED}Error: Could not find tenancy OCID in OCI config.${NC}"
    exit 1
fi

echo -e "${BLUE}Using tenancy: ${TENANCY_OCID}${NC}"

# List all compartments
echo -e "\n${BLUE}Listing compartments...${NC}"
COMPARTMENTS=$(oci iam compartment list --compartment-id "$TENANCY_OCID" --all --query "data[*].id" --raw-output --region "$REGION")
echo -e "${GREEN}Root compartment ID: ${TENANCY_OCID}${NC}"

# Function to list clusters in a compartment
list_clusters_in_compartment() {
    local compartment_id=$1
    local compartment_name=$2
    
    echo -e "\n${BLUE}Checking for clusters in compartment: ${compartment_name}${NC}"
    
    # List clusters in the compartment
    cluster_list=$(oci ce cluster list --compartment-id "$compartment_id" --region "$REGION" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Unable to list clusters in this compartment (possibly no permissions)${NC}"
        return
    fi
    
    # Extract cluster data
    clusters=$(echo "$cluster_list" | jq -r '.data[] | "\(.id) \(.name) \(.lifecycle-state)"' 2>/dev/null)
    
    if [ -z "$clusters" ]; then
        echo -e "${YELLOW}No Kubernetes clusters found in this compartment${NC}"
        return
    fi
    
    # Print cluster information
    echo -e "${GREEN}Found clusters in ${compartment_name}:${NC}"
    echo -e "${BLUE}-----------------------------------------------${NC}"
    echo -e "${BLUE}CLUSTER ID                                 | NAME                | STATE${NC}"
    echo -e "${BLUE}-----------------------------------------------${NC}"
    
    echo "$clusters" | while read -r line; do
        id=$(echo "$line" | cut -d' ' -f1)
        name=$(echo "$line" | cut -d' ' -f2)
        state=$(echo "$line" | cut -d' ' -f3)
        echo -e "${id} | ${name} | ${state}"
    done
    
    echo -e "${BLUE}-----------------------------------------------${NC}"
}

# Check for clusters in the root compartment
list_clusters_in_compartment "$TENANCY_OCID" "Root Compartment"

# Check for clusters in sub-compartments
for compartment_id in $COMPARTMENTS; do
    compartment_name=$(oci iam compartment get --compartment-id "$compartment_id" --query "data.name" --raw-output --region "$REGION" 2>/dev/null)
    if [ -n "$compartment_name" ]; then
        list_clusters_in_compartment "$compartment_id" "$compartment_name"
    fi
done

echo -e "\n${BLUE}==============================================${NC}"
echo -e "${BLUE}               Summary                       ${NC}"
echo -e "${BLUE}==============================================${NC}"

echo -e "\n${GREEN}To use a cluster ID in your GitHub Actions workflow:${NC}"
echo -e "1. Copy the full Cluster ID from above"
echo -e "2. Run the GitHub workflow with this ID provided in the input parameters"
echo -e "3. To check cluster details use: ${YELLOW}oci ce cluster get --cluster-id <CLUSTER_ID> --region ${REGION}${NC}"

echo -e "\n${YELLOW}If no clusters are listed, you'll need to create a Kubernetes cluster first:${NC}"
echo -e "1. Go to your Oracle Cloud console: https://cloud.oracle.com"
echo -e "2. Navigate to Developer Services > Kubernetes Clusters (OKE)"
echo -e "3. Click 'Create Cluster' and follow the wizard (Quick Create is recommended for new users)"
echo -e "4. After creation (5-15 minutes), run this script again to get the cluster ID"

echo -e "\n${BLUE}==============================================${NC}" 