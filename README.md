# ArgoCD Cluster Addons Management

This solution provides a scalable way to manage multiple clusters and their addons through ArgoCD. It implements the App of Apps pattern to manage addon deployments across multiple clusters with environment-based configuration.

## Features
- Centralized addon management across multiple clusters
- Environment-based configuration
- Version control for addon deployments
- Secure secrets management via AWS Secrets Manager
- Support for gradual rollout of addon updates
- Cluster-specific configuration overrides

## Solution Components

### AWS SecretStore Configuration
The solution uses a ClusterSecretStore to access AWS Secrets Manager:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: global-secret-store
spec:
  provider:
    aws:
      service: SecretsManager
      region: eu-west-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
```

This configuration:
- Uses IRSA for authentication
- Connects to AWS Secrets Manager in eu-west-1
- Provides cluster-wide access to secrets

### Addon Configuration Structure
The `values/addons-list.yaml` file defines all available addons:
```yaml
applicationsets:
  - appName: external-secrets    # Name of the addon
    repoURL: https://charts...   # Helm chart repository
    chart: external-secrets      # Chart name
    environments:                # Environment-specific configs
      - env: argocd-control-plane
        version: 0.9.10         # Chart version
        valuesObject: {}        # Optional default values
```

Each addon can have:
- Multiple environment configurations
- Different versions per environment
- Default values via valuesObject
- Custom sync options and configurations

### Value Management

#### Values Structure
The solution uses several value files:
1. `values/clusters.yaml`: Defines clusters and their labels
2. `values/addons-values/defaults.yaml`: Default addon configurations
3. `values/addons-values/clusters/<cluster>/`: Cluster-specific overrides

#### Value Precedence
Values are merged in this order (highest precedence first):
1. Cluster-specific values
2. Environment-specific values from addons-list.yaml
3. Default values from addons-values/defaults.yaml
4. Chart default values

### Datadog Integration Details

The solution manages two types of Datadog secrets:

1. **API Keys**
   - Stored in AWS Secrets Manager
   - One key per cluster
   - Mounted as Kubernetes secrets

2. **Cluster Tags**
   - Stored in cluster AWS secret
   - Configured via dd_tags
   - Used for Datadog agent configuration

#### Secret Structure
```yaml
# API Key Secret
apiVersion: v1
kind: Secret
metadata:
  name: <cluster-name>
stringData:
  api-key: <from-aws-secrets>

# Tags Secret
apiVersion: v1
kind: Secret
metadata:
  name: datadog-tags
stringData:
  DD_TAGS: <from-cluster-secret>
```

### Adding New Addons
To add a new addon to the solution:
1. Add it to `values/addons-list.yaml`:
   ```yaml
   applicationsets:
     - appName: new-addon
       repoURL: https://charts.new-addon.io
       chart: new-addon
       environments:
         - env: dev
           version: 1.0.0
           valuesObject:  # Optional default values
             key: value
   ```
2. Create cluster-specific values in `values/addons-values/clusters/` if needed
3. Enable it via cluster labels in `values/clusters.yaml`

## Prerequisites

### Required Tools & Components
- Kubernetes cluster with ArgoCD installed
- AWS account with access to Secrets Manager
- kubectl and helm installed locally
- External Secrets Operator (ESO) will be installed automatically

### ArgoCD Requirements
- ArgoCD version >= 2.4.0
- ArgoCD Vault Plugin (AVP) installed and configured
- ApplicationSet controller enabled

### AWS Requirements
- AWS Secrets Manager access
- IAM roles and policies configured for ESO
- EKS clusters (if using EKS)

## Installation

### 1. AWS Setup

#### Create Required Secrets
1. **Cluster Credentials**
   Create a secret in AWS Secrets Manager for each cluster:
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

#### Configure IAM Role
Create an IAM role for ESO with the following policy:
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

The IAM role ARN is configured in `values/iam-roles.yaml`:
```yaml
external-secrets:
  role: "arn:aws:iam::111111111111:role/external-secrets-argocd"
```

This role is used by ESO to:
- Fetch cluster credentials for ArgoCD cluster registration
- Access Datadog API keys and tags configuration

### External Secrets Installation
ESO is installed first in the ArgoCD control plane cluster using a special environment:
```yaml
applicationsets:
  - appName: external-secrets
    environments:
      - env: argocd-control-plane  # Special env for control plane installation
        version: 0.9.10
```
This ensures ESO is available before registering remote clusters.

### 2. Configuration

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
     - appName: datadog
       environments:
         - env: dev
           version: 3.25.3
   ```

3. **Set IAM Role**
   Update `values/iam-roles.yaml`:
   ```yaml
   external-secrets:
     role: "arn:aws:iam::111111111111:role/external-secrets-argocd"
   ```

### 3. Deploy
```bash
cd app-of-apps/cluster-addons
helm template . | kubectl apply -f - -n argocd
```

## Usage

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

### Cluster Registration
Before attaching a cluster to ArgoCD:

1. Create a corresponding secret in AWS Secret Manager with the cluster's name
2. Include essential information:
   - `clusterName`
   - `host`
   - `caData`
   - `accountId`
   - `dd_tags` (if using Datadog)

_Note: Consider automating this with Terraform for production environments._

### Managing Addon Versions

#### Default Versions
Set default versions in `values/addons-list.yaml`:
```yaml
environments:
  - env: dev
    version: 3.25.3  # Default version
```

#### Cluster-Specific Versions
Override versions using labels:
```yaml
labels:
  datadog: enabled
  datadog-version: "3.70.7"  # Override version
```

### Cluster-Specific Configurations
Create cluster-specific values in `values/addons-values/clusters/<cluster-name>/<addon>.yaml`:
```yaml
datadog:
  logLevel: DEBUG
  additionalConfig:
    customTag: dev-environment
```

### Datadog Configuration

#### Tags Configuration
Each cluster's AWS Secrets Manager secret must include a `dd_tags` key for proper Datadog tagging:
```json
{
  "dd_tags": "env:prod,region:eu-west-1,project:demo"
}
```

The `dd_tags` value should follow Datadog's tag format: `key1:value1,key2:value2`. Common tags include:
- env: Environment name (prod, staging, dev)
- region: AWS region or datacenter location
- project: Project or team name

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

## Architecture

### Components
- **App of Apps**: Root application managing all addon deployments
- **ApplicationSets**: Dynamic application generation per addon/environment
- **External Secrets**: Secure management of cluster credentials and addon secrets
- **Helm Charts**: Templated addon configurations

### Directory Structure
```
├── app-of-apps/          # Root application
├── charts/              # Helm charts
│   ├── clusters/        # Cluster registration
│   └── datadog-*/      # Addon specific charts
└── values/              # Configuration
    ├── addons-values/   # Addon configurations
    ├── addons-list.yaml # Addon definitions
    ├── clusters.yaml    # Cluster definitions
    └── iam-roles.yaml   # IAM configuration
```

### ArgoCD Configuration Requirements

#### ConfigMap Configuration
ArgoCD needs to be configured with the Vault Plugin. Add the following to your `argocd-cm` ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  configManagementPlugins: |
    - name: argocd-vault-plugin-helm
      init:
        command: ["/bin/sh", "-c"]
        args: ["helm dependency build"]
      generate:
        command: ["sh", "-c"]
        args: ["helm template $ARGOCD_APP_NAME ${HELM_VALUES} . | argocd-vault-plugin generate -"]

  # Optional: Configure cmp-server to use AVP
  cmp.specs: |
    - name: avp-helm
      version: v1.0
      allowConcurrency: true
      discover:
        find:
          command: [sh, -c]
          args: ["find . -name 'Chart.yaml' -o -name 'values.yaml'"]
      generate:
        command: [sh, -c]
        args: ["helm template . | argocd-vault-plugin generate -"]
```

#### Plugin Installation
The AVP plugin needs to be installed in the ArgoCD repo-server. Add this to your repo-server deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: argocd-repo-server
spec:
  template:
    spec:
      containers:
      - name: argocd-repo-server
        volumeMounts:
        - name: custom-tools
          mountPath: /usr/local/bin/argocd-vault-plugin
          subPath: argocd-vault-plugin
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
      volumes:
      - name: custom-tools
        emptyDir: {}
```

This configuration enables:
- AVP plugin for Helm chart templating
- Secret injection into Helm values
- Integration with AWS Secrets Manager via AVP