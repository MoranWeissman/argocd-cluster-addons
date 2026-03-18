#!/bin/bash
set -euo pipefail

# GitHub Repository Credentials Bootstrap Script
# This script creates the ArgoCD repository secret for private GitHub access
# MUST be run BEFORE applying bootstrap/root-app.yaml for private repositories

NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
SECRET_NAME="github-repo-credentials"
REPO_URL="${REPO_URL:-https://github.com/<your-org>/argocd-cluster-addons}"

# AWS Secrets Manager configuration
# Update these values to match your environment
AWS_ACCOUNT="${AWS_ACCOUNT:-111111111111}"
AWS_SECRET_NAME="${AWS_SECRET_NAME:-argocd/management-cluster}"
AWS_REGION="${AWS_REGION:-eu-west-1}"

echo "=================================================="
echo "GitHub Repository Credentials Bootstrap"
echo "=================================================="
echo ""
echo "This script creates the ArgoCD repository secret for private repo access."
echo "Repository: $REPO_URL"
echo "Namespace: $NAMESPACE"
echo "AWS Secret: $AWS_SECRET_NAME (Account: $AWS_ACCOUNT)"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl not found. Please install kubectl first."
    exit 1
fi

# Check if aws CLI is available
if ! command -v aws &> /dev/null; then
    echo "ERROR: aws CLI not found. Please install AWS CLI first."
    exit 1
fi

# Check if we're connected to a cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster. Please configure kubectl first."
    exit 1
fi

# Check if ArgoCD namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "ERROR: Namespace '$NAMESPACE' not found."
    echo "Please ensure ArgoCD is installed first."
    exit 1
fi

# Check if secret already exists
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "WARNING: Secret '$SECRET_NAME' already exists in namespace '$NAMESPACE'."
    read -p "Do you want to replace it? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE"
    echo "Existing secret deleted."
fi

echo ""
echo "Fetching GitHub credentials from AWS Secrets Manager..."
echo ""

# Fetch credentials from AWS Secrets Manager
SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$AWS_SECRET_NAME" \
    --region "$AWS_REGION" \
    --query 'SecretString' \
    --output text 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$SECRET_JSON" ]; then
    echo "ERROR: Failed to fetch secret from AWS Secrets Manager."
    echo "Please ensure:"
    echo "  1. You have AWS credentials configured (aws configure)"
    echo "  2. You have access to account $AWS_ACCOUNT"
    echo "  3. Secret '$AWS_SECRET_NAME' exists in region $AWS_REGION"
    echo "  4. You have permission to access the secret"
    exit 1
fi

# Extract username and token from secret
GITHUB_USER=$(echo "$SECRET_JSON" | jq -r '.github_user // empty')
GITHUB_TOKEN=$(echo "$SECRET_JSON" | jq -r '.github_token // empty')

if [ -z "$GITHUB_USER" ] || [ -z "$GITHUB_TOKEN" ]; then
    echo "ERROR: Failed to extract github_user and github_token from secret."
    echo "Secret must contain keys: 'github_user' and 'github_token'"
    exit 1
fi

echo "Successfully retrieved GitHub credentials"
echo "   Username: $GITHUB_USER"
echo "   Token: ${GITHUB_TOKEN:0:4}****"
echo ""
echo "Creating ArgoCD repository secret..."
echo ""

# Create the ArgoCD repository secret
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET_NAME
  namespace: $NAMESPACE
  labels:
    argocd.argoproj.io/secret-type: repository
    app.kubernetes.io/name: github-repo-credentials
    app.kubernetes.io/component: bootstrap
    app.kubernetes.io/managed-by: manual-bootstrap
type: Opaque
stringData:
  type: git
  url: $REPO_URL
  username: $GITHUB_USER
  password: $GITHUB_TOKEN
EOF

echo ""
echo "GitHub repository secret created successfully!"
echo ""
echo "Verification:"
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE"
echo ""
echo "=================================================="
echo "Next Steps:"
echo "=================================================="
echo "1. Verify the secret was created:"
echo "   kubectl get secret $SECRET_NAME -n $NAMESPACE -o yaml"
echo ""
echo "2. Deploy the root application:"
echo "   kubectl apply -f bootstrap/root-app.yaml"
echo ""
echo "3. Monitor the bootstrap deployment:"
echo "   kubectl get applications -n $NAMESPACE -w"
echo ""
echo "Note: Once ESO is deployed, it will take over management of this"
echo "      secret and keep it synchronized with AWS Secrets Manager."
echo ""
echo "=================================================="
