# Bootstrap Guide

Step-by-step guide to bootstrap the ArgoCD cluster addons solution from scratch.

## Prerequisites

### Required Tools
- `kubectl` configured for your ArgoCD management cluster
- `helm` v3.x
- `aws` CLI (for AWS) or `gcloud` CLI (for GCP)

### ArgoCD Requirements
- ArgoCD >= 2.9.0 installed and running
- ApplicationSet controller enabled (default in ArgoCD >= 2.5)

### Repository Access
For private repositories, store GitHub credentials in your secret store:

```json
{
  "github_user": "your-username",
  "github_token": "ghp_xxxxxxxxxxxx"
}
```

## Bootstrap Steps

### Step 1: Configure IAM / Workload Identity

**AWS (EKS):** Create an IAM role for ESO with IRSA. See [IAM_SETUP.md](IAM_SETUP.md).

**GCP (GKE):** Create a GCP service account with Workload Identity. See [GKE-SETUP.md](GKE-SETUP.md).

### Step 2: Create Cluster Secrets

Create a secret in your secret store for each cluster to be managed.

**AWS Secrets Manager** (named `k8s-<cluster-name>`):
```json
{
  "clusterName": "my-cluster-dev",
  "host": "https://ABCDEF1234.gr7.eu-west-1.eks.amazonaws.com",
  "caData": "LS0tLS1CRUdJTi...",
  "accountId": "111111111111",
  "region": "eu-west-1",
  "dd_tags": "env:dev,region:eu-west-1,project:my-app"
}
```

**GCP Secret Manager** (named `k8s-<cluster-name>`):
```json
{
  "clusterName": "my-cluster-dev",
  "host": "https://10.0.0.1",
  "caData": "LS0tLS1CRUdJTi...",
  "region": "us-central1",
  "dd_tags": "env:dev,region:us-central1,project:my-app"
}
```

### Step 3: Configure Bootstrap Settings

Edit `configuration/bootstrap-config.yaml`:

```yaml
repoURL: 'https://github.com/<your-org>/argocd-cluster-addons.git'
targetRevision: main

hostCluster:
  name: <your-argocd-cluster-name>

bootstrap:
  cloudProvider: aws  # or gcp
  region: eu-west-1
  eso:
    version: 0.16.2
    namespace: external-secrets
    serviceaccount:
      name: external-secrets
      roleArn: "arn:aws:iam::<account-id>:role/<your-eso-role>"
```

Also update `bootstrap/root-app.yaml` with your repository URL.

### Step 4: Configure Clusters and Addons

Edit `configuration/cluster-addons.yaml`:
```yaml
clusters:
  - name: my-cluster-dev
    labels:
      datadog: enabled
      keda: enabled
```

Create per-cluster values: `configuration/addons-clusters-values/my-cluster-dev.yaml`

### Step 5: Bootstrap GitHub Credentials (Private Repos)

```bash
./scripts/create-github-credentials.sh
```

### Step 6: Deploy Root Application

```bash
kubectl apply -f bootstrap/root-app.yaml
```

### Step 7: Monitor Deployment

```bash
kubectl get applications -n argocd -w

# Expected order:
# 1. external-secrets-operator (wave -2)
# 2. clusters (wave -1)
# 3. <addon>-<cluster> applications (wave 0+)
```

## Verification

### Check ESO

```bash
kubectl get pods -n external-secrets
kubectl get clustersecretstore
# global-secret-store should show Valid
```

### Check Cluster Registration

```bash
kubectl get externalsecrets -n argocd
kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=cluster
```

### Check ApplicationSets and Applications

```bash
kubectl get applicationsets -n argocd
kubectl get applications -n argocd
```

## Post-Bootstrap

All changes are GitOps-driven:

```bash
# Example: Update addon version
# Edit configuration/addons-catalog.yaml, commit, push
# ArgoCD automatically detects and syncs

# Example: Add a new cluster
# 1. Create secret in secret store
# 2. Add to cluster-addons.yaml
# 3. Create cluster values file
# 4. Commit and push
```

## Troubleshooting

### ESO Not Starting
- Check IAM role / Workload Identity binding
- Verify service account annotation: `kubectl get sa external-secrets -n external-secrets -o yaml`
- Check ESO logs: `kubectl logs -n external-secrets deployment/external-secrets`

### Cluster Secrets Not Created
- Check ExternalSecret status: `kubectl describe externalsecret -n argocd <cluster-name>`
- Verify secret exists in secret store with `k8s-` prefix

### ApplicationSets Not Generating
- Check cluster labels match addon names
- Verify cluster secret has `argocd.argoproj.io/secret-type: cluster` label
- Check ApplicationSet status: `kubectl describe applicationset -n argocd <name>`

### Applications Not Syncing
- Verify Helm chart version exists in upstream repo
- Check `ignoreMissingValueFiles: true` is set
- Verify cluster values file exists at `configuration/addons-clusters-values/<cluster>.yaml`
