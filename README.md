# ArgoCD Cluster Addons Management

This solution provides a scalable way to manage addons across multiple clusters through ArgoCD. It utilizes ApplicationSets for dynamic addon deployment management, wrapped in an App of Apps pattern for the solution's components. The solution heavily leverages Helm templating for dynamic configuration generation.

## Table of Contents
- [Features](#features)
- [Architecture](#architecture)
  - [Components](#components)
  - [Key Patterns](#key-patterns-used)
- [How It Works](#how-it-works)
  - [External Secrets Operator (ESO)](#external-secrets-operator)
  - [ArgoCD Vault Plugin (AVP)](#argocd-vault-plugin)
  - [Datadog Integration](#datadog-integration)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage Guide](#usage-guide)
- [Troubleshooting](#troubleshooting)

## Features
- Centralized addon management using ApplicationSets
- Environment-based configuration through Helm templating
- Version control and customization for addon deployments
- Integration with AWS Secrets Manager via External Secrets Operator
- Flexible per-cluster addon version selection
- Per-cluster addon configuration customization

## Architecture

### Components
- **Root Application**: Manages the solution's components (ApplicationSets, ESO configuration, etc.)
- **ApplicationSets**: Core engine for dynamic addon deployment across clusters
- **External Secrets**: Fetches and provides cluster credentials and addon secrets from AWS Secrets Manager
- **Helm Charts**: Provides templating and configuration management

### Key Patterns Used
- **ApplicationSets**: Dynamic application generation based on cluster metadata
- **Helm Templating**: Powerful configuration management and value generation
- **External Secrets**: Secure secret injection from AWS Secrets Manager

### Directory Structure
```
├── app-of-apps/          # Root application and ApplicationSets
├── charts/              # Helm charts for components
│   ├── clusters/        # Cluster registration
│   └── datadog-*/      # Addon specific charts
└── values/              # Configuration
    ├── addons-values/   # Addon configurations
    ├── addons-list.yaml # Addon definitions
    ├── clusters.yaml    # Cluster definitions
    └── iam-roles.yaml   # IAM configuration
```

## Prerequisites

### ArgoCD Requirements
- ArgoCD version >= 2.4.0
- ApplicationSet controller enabled

#### Configuration Options
ArgoCD needs the Vault Plugin configured. This can be done in two ways:

1. **Recommended**: Via ArgoCD Helm values
```yaml
server:
  config:
    configManagementPlugins: |
      - name: argocd-vault-plugin-helm
        init:
          command: ["/bin/sh", "-c"]
          args: ["helm dependency build"]
        generate:
          command: ["sh", "-c"]
          args: ["helm template $ARGOCD_APP_NAME ${HELM_VALUES} . | argocd-vault-plugin generate -"]
```

2. Alternatively: Via ConfigMap
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  configManagementPlugins: |
    [plugin configuration as above]
```

#### Plugin Installation
The AVP plugin needs to be installed in the ArgoCD repo-server. We recommend configuring this via ArgoCD Helm values:
```yaml
repoServer:
  volumes:
    - name: custom-tools
      emptyDir: {}
  initContainers:
    - name: download-tools
      image: alpine:3.8
      command: [sh, -c]
      args:
        - wget -O argocd-vault-plugin 
          https://github.com/argoproj-labs/argocd-vault-plugin/releases/download/v1.x.x/argocd-vault-plugin_linux_amd64 &&
          chmod +x argocd-vault-plugin &&
          mv argocd-vault-plugin /custom-tools/
      volumeMounts:
        - mountPath: /custom-tools
          name: custom-tools
```

### AWS Requirements
- AWS Secrets Manager access
- IAM roles and policies for ESO
- EKS clusters (if using EKS)

### Required Tools & Components
- Kubernetes cluster with ArgoCD installed
- AWS account with access to Secrets Manager
- kubectl and helm installed locally
- External Secrets Operator (ESO) will be installed automatically

## Installation

### 1. AWS Setup

#### Configure IAM Role
Create an IAM role for ESO to access AWS Secrets Manager:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            "Resource": [
                "arn:aws:secretsmanager:*:*:secret:datadog-api-keys-integration*",
                "arn:aws:secretsmanager:*:*:secret:cluster-*"
            ]
        }
    ]
}
```

Specify the role ARN in `values/iam-roles.yaml`:
```yaml
external-secrets:
  role: "arn:aws:iam::111111111111:role/external-secrets-argocd"
```

#### Required Secrets in AWS
1. **Cluster Credentials**
   Create a secret for each cluster:
   ```json
   {
     "clusterName": "demo-prod",
     "host": "https://your-cluster-endpoint",
     "caData": "your-cluster-ca-data",
     "accountId": "your-aws-account-id",
     "dd_tags": "env:prod,region:eu-west-1,project:demo"
   }
   ```

2. **Datadog API Keys** (if using Datadog)
   Create a secret at path `datadog-api-keys-integration`:
   ```json
   {
     "demo-prod": "your-datadog-api-key-for-demo-prod",
     "demo-staging": "your-datadog-api-key-for-demo-staging"
   }
   ```

### 2. Solution Configuration

1. **Define Clusters**
   Update `values/clusters.yaml`:
   ```yaml
   clusters:
     - name: cluster-1
       labels:
         env: dev
         datadog: enabled
   ```

2. **Configure Addons**
   Update `values/addons-list.yaml`:
   ```yaml
   applicationsets:
     - appName: external-secrets
       environments:
         - env: argocd-control-plane  # Special env for control plane
           version: 0.9.10
         - env: dev
           version: 0.9.10
   ```

### 3. Deploy
```bash
cd app-of-apps/cluster-addons
helm template . | kubectl apply -f - -n argocd
```

## Solution Components

### ApplicationSet Configuration
The solution uses ApplicationSets to dynamically manage addon deployments:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: addon-name-environment
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            env: dev
            addon-name: enabled
  template:
    spec:
      source:
        helm:
          valueFiles:
          - '$values/values/addons-values/clusters/{{name}}/addon-name.yaml'
```

### Value Management

#### Configuration Layers
The solution uses several configuration layers:
1. `values/clusters.yaml`: Cluster definitions and labels
2. `values/addons-values/defaults.yaml`: Base addon configurations
3. `values/addons-values/clusters/<cluster>/`: Cluster-specific configurations

#### Value Precedence
Values are merged in this order:
1. Cluster-specific configurations
2. Environment-specific values from addons-list.yaml
3. Default values from addons-values/defaults.yaml
4. Chart default values

### Datadog Integration

The solution integrates with Datadog using two types of configurations:

1. **API Keys**
   - Fetched from AWS Secrets Manager
   - Provided to Datadog agent via Kubernetes secrets

2. **Cluster Tags**
   - Retrieved from cluster AWS secret
   - Configured via dd_tags field
   - Applied to all Datadog telemetry

#### Tags Configuration
Each cluster's AWS Secrets Manager secret must include a `dd_tags` key:
```json
{
  "dd_tags": "env:prod,region:eu-west-1,project:demo"
}
```

The `dd_tags` value follows Datadog's tag format (`key1:value1,key2:value2`). Common tags include:
- env: Environment name (prod, staging, dev)
- region: AWS region or datacenter location
- project: Project or team name

These tags will be:
- Automatically applied to all Datadog telemetry
- Available for filtering and organizing in Datadog UI
- Used for cost allocation and environment separation

## How It Works

### External Secrets Operator
ESO is a Kubernetes operator that fetches secrets from external APIs and injects them as Kubernetes Secrets. In this solution:

1. ESO is installed first in the control plane cluster
2. It uses AWS IAM roles to authenticate with AWS Secrets Manager
3. It creates two types of secrets:
   - Cluster credentials for ArgoCD cluster registration
   - Datadog API keys for monitoring

Example flow:
```
AWS Secrets Manager -> ESO -> Kubernetes Secrets -> Used by Applications
```

### ArgoCD Vault Plugin
AVP is a plugin that injects secrets during the ArgoCD sync process. In this solution:

1. AVP runs during Helm template rendering
2. It replaces special markers in YAML files with actual secrets
3. Used primarily for:
   - Injecting Datadog tags from cluster secrets
   - Managing sensitive configuration values

Example flow:
```
Helm Template -> AVP -> Rendered Manifests -> Applied by ArgoCD
```

### Datadog Integration
Datadog is configured using multiple components:

1. **API Keys**
   - Stored in AWS Secrets Manager
   - One key per cluster
   - Fetched by ESO and mounted as Kubernetes secrets

2. **Cluster Tags**
   - Stored in cluster AWS secret as `dd_tags`
   - Format: `key1:value1,key2:value2`
   - Used for:
     * Environment separation
     * Cost allocation
     * Metric filtering
     * Alert routing

Example `dd_tags`:
```json
{
  "dd_tags": "env:prod,region:eu-west-1,project:demo,team:platform"
}
```

These tags help organize and filter:
- Metrics
- Logs
- Traces
- Alerts
- Dashboards

## Usage Guide

### Managing Clusters

#### Adding a New Cluster
1. Create cluster secret in AWS Secrets Manager
2. Add cluster to `values/clusters.yaml`:
   ```yaml
   clusters:
     - name: my-new-cluster
       labels:
         env: prod
   ```

#### Enabling Addons
Add the appropriate label to enable addons:
```yaml
labels:
  datadog: enabled
  keda: enabled
```

### Managing Addon Versions

#### Default Versions
Set default versions in `values/addons-list.yaml`:
```yaml
environments:
  - env: dev
    version: 3.25.3  # Default version
```

#### Per-Cluster Versions
Specify versions for specific clusters using labels:
```yaml
labels:
  datadog: enabled
  datadog-version: "3.70.7"  # Cluster-specific version
```

### Cluster-Specific Configurations
Create configurations in `values/addons-values/clusters/<cluster-name>/<addon>.yaml`:
```yaml
datadog:
  logLevel: DEBUG
  additionalConfig:
    customTag: dev-environment
```

## Troubleshooting

### Common Issues

1. **ApplicationSet Not Generating Applications**
   - Verify cluster labels match environment
   - Check cluster secret exists in ArgoCD
   - Ensure cluster is properly registered

2. **External Secrets Failures**
   - Verify IAM role permissions
   - Check AWS Secret exists and format is correct
   - Validate ESO is running properly

3. **Addon Deployment Issues**
   - Check addon version compatibility
   - Verify values file exists for cluster
   - Check for syntax errors in values files