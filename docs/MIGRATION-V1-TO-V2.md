# Migration Guide: V1 to V2

This guide walks you through migrating from V1 (the original `app-of-apps/` structure) to V2 (the new `bootstrap/` structure).

## Overview

V2 is a complete restructure — not an incremental upgrade. The directory layout, configuration format, secret management approach, and ApplicationSet patterns have all changed.

**What changed:**

| Aspect | V1 | V2 |
|--------|----|----|
| Root application | `app-of-apps/cluster-addons/` | `bootstrap/` |
| Cluster definitions | `values/clusters.yaml` | `configuration/cluster-addons.yaml` |
| Addon definitions | `values/addons-list.yaml` (per-environment) | `configuration/addons-catalog.yaml` (flat list) |
| Global defaults | `values/addons-values/defaults.yaml` | `configuration/addons-global-values/<addon>.yaml` (one file per addon) |
| Per-cluster config | `values/addons-values/clusters/<cluster>/<addon>.yaml` (one file per addon per cluster) | `configuration/addons-clusters-values/<cluster>.yaml` (single file per cluster) |
| Secret management | AVP + ESO | ESO only |
| IAM roles | `values/iam-roles.yaml` | Injected per-cluster via ApplicationSet helpers |

## Prerequisites

Before migrating:

- [ ] You have V1 running and know which clusters/addons are deployed
- [ ] You have access to your AWS Secrets Manager secrets
- [ ] You have `kubectl` access to the ArgoCD management cluster
- [ ] You've backed up your V1 configuration (or can reference the `v1` git tag)

## Step-by-Step Migration

### Step 1: Document Your Current State

From your V1 repo, capture what you have deployed.

**Clusters and their addons:**
```bash
# From values/clusters.yaml, note each cluster and its labels
cat values/clusters.yaml
```

**Addon versions:**
```bash
# From values/addons-list.yaml, note versions per environment
cat values/addons-list.yaml
```

**Per-cluster overrides:**
```bash
# List all cluster-specific value files
find values/addons-values/clusters/ -name "*.yaml"
```

**IAM roles:**
```bash
cat values/iam-roles.yaml
```

Save this information — you'll need it for Steps 3-5.

### Step 2: Update to V2 Code

```bash
# Tag current state for reference
git tag v1

# Pull the V2 changes (or merge the V2 branch)
git pull origin main
# or: git merge v2-enterprise-evolution
```

After this, your repo will have the new V2 structure. The old `app-of-apps/`, `values/` directories are gone.

### Step 3: Configure Bootstrap

Edit `configuration/bootstrap-config.yaml`:

```yaml
# Set your repo URL
repoURL: 'https://github.com/<your-org>/argocd-cluster-addons.git'
targetRevision: main
githubUsername: <your-github-username>

# Set your management cluster name
hostCluster:
  name: <your-argocd-cluster-name>

# Configure ESO
bootstrap:
  region: <your-aws-region>
  eso:
    version: 0.16.2
    namespace: external-secrets
    serviceaccount:
      name: external-secrets
      roleArn: "arn:aws:iam::<your-account-id>:role/<your-eso-role>"
```

Also update `bootstrap/root-app.yaml` with your repo URL.

### Step 4: Migrate Addon Catalog

**V1 format** (`values/addons-list.yaml`):
```yaml
applicationsets:
  - appName: keda
    repoURL: https://kedacore.github.io/charts
    chart: keda
    environments:
      - env: dev
        version: 2.12.0
      - env: prod
        version: 2.12.0
```

**V2 format** (`configuration/addons-catalog.yaml`):
```yaml
applicationsets:
  - appName: keda
    repoURL: https://kedacore.github.io/charts
    chart: keda
    version: 2.14.2    # Single default version (override per-cluster via labels)
    # namespace: keda   # Optional, defaults to appName
```

Key differences:
- No more `environments` array — version is a single default
- Per-cluster version overrides use labels instead: `keda-version: "2.12.0"`
- `namespace` is optional (defaults to `appName`)

### Step 5: Migrate Cluster Definitions

**V1 format** (`values/clusters.yaml`):
```yaml
clusters:
  - name: cluster-1
    labels:
      env: dev
      datadog: enabled
      datadog-version: "3.70.7"
      keda: enabled
```

**V2 format** (`configuration/cluster-addons.yaml`):
```yaml
clusters:
  - name: cluster-1
    labels:
      datadog: enabled
      datadog-version: "3.70.7"
      keda: enabled
```

Key differences:
- The `env` label is no longer needed (V2 doesn't use environment-based filtering)
- Addon labels remain the same: `<addon>: enabled`
- Version overrides remain the same: `<addon>-version: "X.Y.Z"`

### Step 6: Migrate Per-Cluster Values

This is the biggest change. V1 used separate files per addon per cluster. V2 uses a single file per cluster.

**V1** (multiple files):
```
values/addons-values/clusters/cluster-1/datadog.yaml
values/addons-values/clusters/cluster-1/keda.yaml
```

**V2** (single file):
```
configuration/addons-clusters-values/cluster-1.yaml
```

**How to consolidate:**

1. Create the cluster file with global values and YAML anchors:
```yaml
clusterGlobalValues:
  env: &env dev
  clusterName: &clusterName cluster-1
  region: &region eu-west-1
  projectName: my-project
  accountId: 111111111111
```

2. Add each addon's config as a top-level key:
```yaml
# From values/addons-values/clusters/cluster-1/datadog.yaml
datadog:
  datadog:
    clusterName: *clusterName
    # ... rest of your datadog config

# From values/addons-values/clusters/cluster-1/keda.yaml
keda:
  serviceAccount:
    operator:
      annotations:
        eks.amazonaws.com/role-arn: arn:aws:iam::111111111111:role/keda-cluster-1
  # ... rest of your keda config
```

The addon key name must match the `appName` in `addons-catalog.yaml`.

### Step 7: Migrate Global Defaults

**V1**: All defaults in one file (`values/addons-values/defaults.yaml`)

**V2**: One file per addon (`configuration/addons-global-values/<addon>.yaml`)

Split your `defaults.yaml` into individual files. Each file should contain only that addon's default values. See the example files provided in V2 for the format.

### Step 8: Remove AVP Configuration

V2 uses ESO exclusively. If you had AVP configured:

1. Remove the AVP plugin from your ArgoCD repo-server
2. Remove any `avp.kubernetes.io/path` annotations from your manifests
3. Secrets are now handled by ExternalSecrets (the `charts/datadog-apikey/` chart handles Datadog API keys)

### Step 9: Set Up Datadog Project Mappings (If Using Datadog)

Create `configuration/datadog-project-mappings.yaml` mapping each cluster to its Datadog project name:

```yaml
datadogProjectMappings:
  cluster-1:
    projectName: my-project
    env: dev
```

This is used by the `datadog-apikey` chart to look up the correct API key property from AWS Secrets Manager.

### Step 10: Verify AWS Secrets

Ensure your AWS Secrets Manager secrets follow the V2 naming convention:

- Cluster credentials: `k8s-<cluster-name>` (same as V1)
- Datadog API keys: `datadog-api-keys-integration` with property `<projectName>-<env>`

The secret format is the same as V1, but V2 also reads `region` and `accountId` fields:
```json
{
  "clusterName": "cluster-1",
  "host": "https://...",
  "caData": "...",
  "accountId": "111111111111",
  "region": "eu-west-1",
  "dd_tags": "env:dev,region:eu-west-1,project:my-project"
}
```

### Step 11: Deploy V2

```bash
# For private repos
./scripts/create-github-credentials.sh

# Deploy the new root application
kubectl apply -f bootstrap/root-app.yaml
```

### Step 12: Clean Up V1

After V2 is running and all addons are healthy:

```bash
# Remove the old V1 root application (if it had a different name)
kubectl delete application <v1-root-app-name> -n argocd
```

## Rollback

If something goes wrong:

```bash
# Switch back to V1
git checkout v1

# Redeploy V1 root application
cd app-of-apps/cluster-addons
helm template . | kubectl apply -f - -n argocd
```

## Quick Reference: File Mapping

| V1 File | V2 Equivalent |
|---------|---------------|
| `app-of-apps/cluster-addons/Chart.yaml` | `bootstrap/Chart.yaml` |
| `app-of-apps/cluster-addons/templates/appsets/applicationset.yaml` | `bootstrap/templates/addons-appset.yaml` |
| `app-of-apps/cluster-addons/templates/addons-app.yaml` | `bootstrap/root-app.yaml` |
| `app-of-apps/cluster-addons/templates/apps/remote-clusters.yaml` | `bootstrap/templates/clusters.yaml` |
| `app-of-apps/cluster-addons/templates/apps/datadog-apikey-secret.yaml` | `charts/datadog-apikey/` (multi-source) |
| `app-of-apps/cluster-addons/templates/apps/datadog-tags.yaml` | Removed (tags injected via ApplicationSet helper) |
| `values/clusters.yaml` | `configuration/cluster-addons.yaml` |
| `values/addons-list.yaml` | `configuration/addons-catalog.yaml` |
| `values/addons-values/defaults.yaml` | `configuration/addons-global-values/<addon>.yaml` |
| `values/addons-values/clusters/<cluster>/<addon>.yaml` | `configuration/addons-clusters-values/<cluster>.yaml` |
| `values/iam-roles.yaml` | Removed (IRSA injected per-cluster via helpers) |
| `values/global.yaml` | `configuration/bootstrap-config.yaml` |
| `charts/clusters/templates/remote-cluster-template-es.yaml` | `charts/clusters/templates/cluster-external-secret.yaml` |
| `charts/clusters/templates/cluster-secret-store.yaml` | `charts/eso-configuration/templates/cluster-secret-store.yaml` |
| `charts/clusters/templates/external-secrets-sa.yaml` | Removed (managed by ESO bootstrap) |
| `charts/datadog-apikey-secret/` | `charts/datadog-apikey/` |
| `charts/datadog-tags/` | Removed (tags injected via cluster annotations) |
| *(not in V1)* | `bootstrap/templates/_helpers.tpl` |
| *(not in V1)* | `bootstrap/templates/eso.yaml` |
| *(not in V1)* | `bootstrap/templates/karpenter-nodepools-appset.yaml` |
| *(not in V1)* | `configuration/addons-global-values/nodepools-config-values/` |
| *(not in V1)* | `configuration/karpenter-nodepools-config.yaml` |
| *(not in V1)* | `configuration/datadog-project-mappings.yaml` |
| *(not in V1)* | `scripts/create-github-credentials.sh` |
