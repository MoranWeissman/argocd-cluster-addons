# ArgoCD Cluster Add-ons Management Guide

Welcome to the official guide for managing Kubernetes cluster add-ons via ArgoCD. This wiki is designed for DevOps engineers to simplify the deployment and management of cluster add-ons across multiple remote clusters.

## Table of Contents
1. [Introduction](#introduction)
2. [Why Use This Solution?](#why-use-this-solution)
3. [Workflow Standards](#workflow-standards)
4. [Bootstrap Installation](#bootstrap-installation)
5. [Usage](#usage)
   - [Adding a Cluster](#adding-a-cluster)
   - [Enabling an Addon for a Cluster](#enabling-an-addon-for-a-cluster)
   - [Updating Default Addon Configurations](#updating-default-addon-configurations)
   - [Overriding Addon Configurations for a Specific Cluster](#overriding-addon-configurations-for-a-specific-cluster)
6. [Managing Addon Values](#managing-addon-values)
7. [Repository Structure](#repository-structure)
7. [Examples](#examples)
   - [Adding a New Cluster Example](#adding-a-new-cluster-example)
   - [Enabling an Addon Example](#enabling-an-addon-example)
   - [Updating Default Configurations Example](#updating-default-configurations-example)
   - [Cluster-Specific Overrides Example](#cluster-specific-overrides-example)


## Workflow Standards

Before diving into the technical details of managing cluster add-ons with ArgoCD, it is crucial to understand the workflow standards set for configuration changes:

- **Committing Changes**:
  - All changes to the cluster configurations are to be made through pull requests. Direct commits to the main branch are not allowed to ensure a reviewable and auditable trail of modifications.

- **Review and Approval**:
  - Pull requests must be reviewed providing a layer of scrutiny to uphold the quality and security of changes.

- **Merging Process**:
  - Merging of pull requests is contingent upon successful reviews and approvals from the required personnel.

This workflow is integral to our operations and ensures that all changes are implemented responsibly and in accordance with established protocols.

## Introduction
This solution employs ArgoCD to manage the deployment of various Kubernetes add-ons across multiple clusters from a centralized point, leveraging Helm for configuration templating.

## Why Use This Solution?
Utilizing a GitOps approach, this solution ensures that add-on deployments are consistent, declarative, and version-controlled, thereby enhancing the maintainability and scalability of cluster management.

## Bootstrap Installation
To install the cluster add-ons:

1. Connect to your Kubernetes cluster context.
2. Navigate to the `app-of-apps` folder in your local copy of this repository.
3. Run the following command in each `app-of-apps` directory:
```
helm template . | kubectl apply -f - -n argocd
```
Start with `cluster-addons`, followed by `datadog-apiKeys`.

## Usage

### Adding a Cluster
Before attaching a cluster to ArgoCD:

- Create a corresponding secret in AWS Secret Manager with the cluster's name.
- Include essential information: `clusterName`, `host`, `caData`, and `accountId`.

_Note to self: Ask the infra team to automate this with Terraform if possible._

After creating the AWS secret:

- Update `clusters.yaml` with the new cluster's information.
- Initially, apply only the `env` label to the cluster configuration.
- Push the changes and synchronize or wait for ArgoCD to automatically sync the clusters application.

#### Example: Adding a New Cluster
To add a new cluster to ArgoCD, you would:
1. Navigate to the `values/clusters.yaml` file.
2. Insert the details of the cluster in the following format:
    ```yaml
    clusters:
      - name: my-new-cluster
        labels:
          env: prod
    ```
3. Submit the changes via a pull request for review.

### Enabling an Addon for a Cluster
To manage an addon:

- Follow the structure defined in `addons-list.yaml`.
- After syncing `cluster-addons-root`, use labels in `clusters.yaml` to control addon deployments on specific clusters.

#### Example: Enabling an Addon
To enable an addon for a cluster:
1. Locate the `clusters.yaml` file in the `values` directory.
2. Add the addon label to the cluster configuration:
    ```yaml
    clusters:
      - name: my-cluster
        labels:
          datadog: enabled
    ```
3. Create a pull request with this change for the necessary approvals.


### Updating Default Addon Configurations
When installing Datadog:

- Optionally, create a `datadogApiKey` in AWS Secret Manager to auto-generate the required Kubernetes secret.
- Add a dummy or placeholder value for `datadogApiKey` if Datadog is not in use immediately.

_Note: The `datadog-apikeys` app-of-apps is only necessary when utilizing Datadog._

#### Example: Updating Default Configurations
Suppose you need to change the default log level for Datadog across all clusters:
1. Open `values/addons-config/defaults.yaml`.
2. Modify the `datadog` configuration:
    ```yaml
    datadog:
      logLevel: WARN
    ```

## Managing Addon Values

### Updating Default Addon Configurations
Default values for addons are specified in `values/addons-config/defaults.yaml`, which are applied across all environments. Ensure to update this file when introducing new addons.

### Overriding Addon Configurations for a Specific Cluster
For individual cluster configurations, create override files within the `values/addons-config/overrides/<cluster-name>/` directory. This allows for cluster-specific customization of addons.

#### Example: Cluster-Specific Overrides
If you need to set a specific Datadog log level for the `dev-cluster`, you would:
1. Edit the file at `values/addons-config/overrides/dev-cluster/datadog.yaml`.
2. Set your specific configurations:
    ```yaml
    datadog:
      logLevel: DEBUG
    ```
    
## Repository Structure

Below is the directory tree of this repository:
```
├── README.md
├── app-of-apps
│ ├── cluster-addons
│ │ ├── Chart.yaml
│ │ ├── templates
│ │ │ ├── addons-app.yaml
│ │ │ ├── apps
│ │ │ │ ├── argocd-config.yaml
│ │ │ │ └── remote-clusters.yaml
│ │ │ └── appsets
│ │ │ └── applicationset.yaml
│ │ └── values.yaml
│ └── datadog-apikeys
│ ├── Chart.yaml
│ ├── templates
│ │ ├── apps
│ │ │ └── datadog-apikey-secret.yaml
│ │ └── datadog-apikeys.yaml
│ └── values.yaml
├── charts
│ ├── argocd-config
│ │ ├── Chart.yaml
│ │ ├── templates
│ │ │ ├── argo-cd-argocd-repo-server-deployment.yaml
│ │ │ ├── argo-cd-argocd-repo-server-sa.yaml
│ │ │ ├── argocd-application-controller-sa.yaml
│ │ │ ├── argocd-applicationset-controller-sa.yaml
│ │ │ ├── argocd-cm.yaml
│ │ │ ├── argocd-server-sa.yaml
│ │ │ └── cmp-plugin.yaml
│ │ └── values.yaml
│ ├── clusters
│ │ ├── Chart.yaml
│ │ ├── templates
│ │ │ ├── cluster-secret-store.yaml
│ │ │ └── remote-cluster-template-es.yaml
│ │ └── values.yaml
│ └── datadog-apikey-secret
│ ├── Chart.yaml
│ ├── templates
│ │ └── datadog-apikey-secret.yaml
│ └── values.yaml
└── values
├── addons-config
│ ├── defaults.yaml
│ └── overrides
│ └── swine-dev
│ ├── datadog.yaml
│ └── keda.yaml
├── addons-list.yaml
├── clusters.yaml
└── global.yaml
```
---