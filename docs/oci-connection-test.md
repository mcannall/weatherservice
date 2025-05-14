# Testing Oracle Cloud Connectivity

This guide explains how to test the Oracle Cloud Infrastructure (OCI) connectivity from GitHub Actions.

## Prerequisites

Before running the test workflow, make sure you have the following secrets configured in your GitHub repository:

1. `OCI_CLI_USER` - Your Oracle Cloud user OCID
2. `OCI_CLI_TENANCY` - Your Oracle Cloud tenancy OCID
3. `OCI_CLI_FINGERPRINT` - Your API key fingerprint
4. `OCI_PRIVATE_KEY` - Your private key in PEM format (the entire content of the private key file)
5. `OCI_REGION` - Your Oracle Cloud region (e.g., us-chicago-1)
6. `OCI_CLUSTER_ID` - Your Oracle Kubernetes Engine (OKE) cluster OCID (only needed for OKE tests)

## How to Run the Test Workflow

1. Go to your GitHub repository
2. Click on the "Actions" tab
3. In the left sidebar, find and click on "Test Oracle Cloud Connectivity"
4. Click the "Run workflow" button
5. You can customize the test by checking/unchecking these options:
   - "Run Oracle list command" - Lists additional OCI resources (regions, compartments)
   - "Test OKE Kubernetes connection" - Tests connection to your OKE Kubernetes cluster
6. Click "Run workflow" to start the test

## Expected Results

If the workflow runs successfully, it means your GitHub Actions can authenticate with OCI and perform basic operations. The workflow will:

1. Install the OCI CLI
2. Configure the OCI CLI with your credentials
3. Test basic connectivity by listing availability domains
4. (Optional) List additional OCI resources
5. (Optional) Test the connection to your OKE Kubernetes cluster

## Troubleshooting

If the workflow fails, here are some common issues and solutions:

### Invalid Credentials

- **Symptom**: Error messages about authentication or authorization failure
- **Solution**: Verify that all OCI secrets are correctly configured in GitHub repository settings

### Malformed Private Key

- **Symptom**: Error about invalid private key format
- **Solution**: Make sure the private key is in PEM format and includes both the header and footer lines (`-----BEGIN RSA PRIVATE KEY-----` and `-----END RSA PRIVATE KEY-----`)

### OKE Cluster Connection Issues

- **Symptom**: Error connecting to OKE cluster
- **Solution**: Verify the `OCI_CLUSTER_ID` is correct and that your OCI user has permission to access the cluster

### API Limits

- **Symptom**: Rate limiting errors
- **Solution**: Reduce the frequency of workflow runs or contact Oracle support to increase your API limits 