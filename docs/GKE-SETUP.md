# GKE (Google Cloud) Setup Guide

> **Community-contributed feature.** GKE support was developed based on a community contribution and has not been tested end-to-end by the maintainers (who run on AWS/EKS). If you encounter issues or have improvements, please open an issue or PR.

This guide covers the GCP-specific prerequisites and configuration for running ArgoCD Cluster Addons on GKE clusters with GCP Secret Manager.

## Overview

When `bootstrap.cloudProvider` is set to `gcp`, the solution uses:
- **GCP Secret Manager** instead of AWS Secrets Manager
- **Workload Identity** instead of IRSA for service account authentication
- **`argocd-k8s-auth gcp`** instead of `argocd-k8s-auth aws` for cluster authentication

All other functionality (ApplicationSets, addons, values hierarchy) works identically.

## Prerequisites

### GCP Projects
- A GCP project for the ArgoCD management cluster (where ESO is installed)
- One or more GCP projects containing target GKE clusters

### GKE Clusters
- Workload Identity enabled on all clusters
- ArgoCD management cluster can reach target cluster API servers (firewall / authorized networks)

### Service Accounts

**1. External Secrets Operator (ESO)**

Create a GCP service account for ESO to access Secret Manager:

```bash
GCP_PROJECT="my-argocd-project"
ESO_SA_NAME="external-secrets"
ESO_K8S_SA="external-secrets"
ESO_NAMESPACE="external-secrets"

# Create GCP service account
gcloud iam service-accounts create $ESO_SA_NAME \
  --project $GCP_PROJECT \
  --display-name "External Secrets Operator"

# Grant Secret Manager access
gcloud projects add-iam-policy-binding $GCP_PROJECT \
  --member="serviceAccount:${ESO_SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Bind Workload Identity
gcloud iam service-accounts add-iam-policy-binding \
  ${ESO_SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:${GCP_PROJECT}.svc.id.goog[${ESO_NAMESPACE}/${ESO_K8S_SA}]" \
  --project $GCP_PROJECT
```

**2. ArgoCD (for cluster authentication)**

ArgoCD needs a service account with access to target GKE clusters:

```bash
ARGO_SA_NAME="argocd"
ARGO_NAMESPACE="argocd"

# Create GCP service account for ArgoCD
gcloud iam service-accounts create $ARGO_SA_NAME \
  --project $GCP_PROJECT \
  --display-name "ArgoCD Cluster Access"

# Grant GKE access on target project
gcloud projects add-iam-policy-binding $TARGET_PROJECT \
  --member="serviceAccount:${ARGO_SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --role="roles/container.clusterViewer"

# Bind Workload Identity for ArgoCD server
gcloud iam service-accounts add-iam-policy-binding \
  ${ARGO_SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:${GCP_PROJECT}.svc.id.goog[${ARGO_NAMESPACE}/argocd-server]" \
  --project $GCP_PROJECT

# Same for ArgoCD application controller
gcloud iam service-accounts add-iam-policy-binding \
  ${ARGO_SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:${GCP_PROJECT}.svc.id.goog[${ARGO_NAMESPACE}/argocd-application-controller]" \
  --project $GCP_PROJECT
```

## Required Secrets in GCP Secret Manager

### Cluster Credentials

Create a secret for each cluster, named `k8s-<cluster-name>`:

```bash
# Using Terraform (recommended)
# See Terraform example below

# Or using gcloud CLI
gcloud secrets create k8s-my-gke-cluster-dev \
  --project $GCP_PROJECT \
  --replication-policy="automatic"

gcloud secrets versions add k8s-my-gke-cluster-dev \
  --project $GCP_PROJECT \
  --data-file=- <<EOF
{
  "clusterName": "my-gke-cluster-dev",
  "host": "https://10.0.0.1",
  "caData": "LS0tLS1CRUdJTi...",
  "region": "us-central1",
  "dd_tags": "env:dev,region:us-central1,project:my-app"
}
EOF
```

### Datadog API Keys (if using Datadog)

Same as AWS — create a secret named `datadog-api-keys-integration`:

```bash
gcloud secrets create datadog-api-keys-integration \
  --project $GCP_PROJECT \
  --replication-policy="automatic"

gcloud secrets versions add datadog-api-keys-integration \
  --project $GCP_PROJECT \
  --data-file=- <<EOF
{
  "my-app-dev": "your-datadog-api-key"
}
EOF
```

## Terraform Example

Store GKE cluster credentials in GCP Secret Manager automatically:

```hcl
locals {
  argocd_project = "my-argocd-project"
}

data "google_container_cluster" "target" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id
}

resource "google_secret_manager_secret" "cluster" {
  project   = local.argocd_project
  secret_id = "k8s-${var.cluster_name}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "cluster" {
  secret      = google_secret_manager_secret.cluster.id
  secret_data = jsonencode({
    clusterName = data.google_container_cluster.target.name
    host        = "https://${data.google_container_cluster.target.endpoint}"
    caData      = data.google_container_cluster.target.master_auth[0].cluster_ca_certificate
    region      = var.region
    gcpProjectId = var.project_id
    dd_tags     = "env:${var.env},region:${var.region},project:${var.project_name}"
  })
}
```

## Configuration

### 1. Set Cloud Provider

Edit `configuration/bootstrap-config.yaml`:

```yaml
bootstrap:
  cloudProvider: gcp
  region: us-central1

  eso:
    version: 0.16.2
    namespace: external-secrets
    serviceaccount:
      name: external-secrets
      gcpServiceAccount: "external-secrets@my-argocd-project.iam.gserviceaccount.com"

  gcp:
    projectID: my-argocd-project
```

### 2. Define Clusters

Edit `configuration/cluster-addons.yaml`:

```yaml
clusters:
  - name: my-gke-cluster-dev
    labels:
      keda: enabled
      external-secrets: enabled
      cert-manager: enabled
```

### 3. Create Cluster Values

Create `configuration/addons-clusters-values/my-gke-cluster-dev.yaml`:

```yaml
clusterGlobalValues:
  env: &env dev
  clusterName: &clusterName my-gke-cluster-dev
  region: &region us-central1
  projectName: my-app
  gcpProjectId: my-gcp-project-123

keda:
  serviceAccount:
    operator:
      annotations:
        iam.gke.io/gcp-service-account: keda@my-gcp-project-123.iam.gserviceaccount.com
```

### 4. Bootstrap

```bash
kubectl apply -f bootstrap/root-app.yaml
```

## Differences from AWS Setup

| Aspect | AWS (EKS) | GCP (GKE) |
|--------|-----------|-----------|
| Secret store | AWS Secrets Manager | GCP Secret Manager |
| Service account auth | IRSA (`eks.amazonaws.com/role-arn`) | Workload Identity (`iam.gke.io/gcp-service-account`) |
| Cluster auth | `argocd-k8s-auth aws --cluster-name --role-arn` | `argocd-k8s-auth gcp` |
| Secret structure | `dataFrom.extract` (all properties at once) | `data` (individual properties) |
| Auto Mode | EKS Auto Mode + Karpenter NodePools | Not applicable (use GKE Autopilot natively) |
| Account identifier | `accountId` (AWS account ID) | `gcpProjectId` (GCP project ID) |

## Notes

- **EKS Auto Mode / Karpenter NodePools** are AWS-specific and will not deploy on GKE clusters (the `eksAutoMode` label won't be set)
- **Datadog** works the same on both providers — API keys are fetched from Secret Manager regardless of cloud provider
- GKE Autopilot clusters handle node scheduling natively, so no nodepool configs are needed
- Make sure ArgoCD's NAT gateway IP is in the GKE cluster's master authorized networks
