# Values Guide

How the layered values architecture works in this solution.

## Overview

```
┌─────────────────────────────────────────────┐
│ configuration/bootstrap-config.yaml         │
│ (Bootstrap infrastructure settings)         │
└───────────────────┬─────────────────────────┘
                    │
      ┌─────────────┼─────────────┐
      │             │             │
      ▼             ▼             ▼
┌───────────┐ ┌───────────┐ ┌───────────┐
│ Addon     │ │ Cluster   │ │ Global    │
│ Catalog   │ │ Addons    │ │ Values    │
└───────────┘ └───────────┘ └───────────┘
      │             │             │
      └─────────────┼─────────────┘
                    │
                    ▼
         ┌─────────────────┐
         │ Cluster-Specific │
         │ Values           │
         └─────────────────┘
```

## Configuration Files

### `configuration/bootstrap-config.yaml`

Bootstrap infrastructure settings: repo URL, cloud provider, ESO config.

| Value | Purpose |
|-------|---------|
| `repoURL` | Git repository URL |
| `targetRevision` | Branch/tag to track |
| `hostCluster.name` | ArgoCD management cluster name |
| `bootstrap.cloudProvider` | `aws` or `gcp` |
| `bootstrap.region` | Cloud region for ESO |
| `bootstrap.eso.*` | ESO version, namespace, service account |

### `configuration/addons-catalog.yaml`

Available addons catalog — Helm chart repos and versions.

| Field | Required | Purpose |
|-------|----------|---------|
| `appName` | Yes | Addon name (matches cluster label) |
| `repoURL` | Yes | Helm repository URL |
| `chart` | Yes | Helm chart name |
| `version` | Yes | Default chart version |
| `namespace` | No | Custom namespace (defaults to appName) |
| `ignoreDifferences` | No | ArgoCD ignore rules |
| `inMigration` | No | Enable migration mode |

### `configuration/cluster-addons.yaml`

Cluster registry with addon assignments via labels.

```yaml
clusters:
  - name: my-cluster-dev
    labels:
      datadog: enabled
      datadog-version: "3.70.7"  # Optional version override
      keda: enabled
```

### `configuration/addons-global-values/<addon>.yaml`

Global defaults per addon — applied to ALL clusters.

### `configuration/addons-clusters-values/<cluster>.yaml`

Per-cluster overrides — single file per cluster with YAML anchors.

```yaml
clusterGlobalValues:
  env: &env dev
  clusterName: &clusterName my-cluster-dev
  region: &region eu-west-1
  projectName: my-app

datadog:
  datadog:
    clusterName: *clusterName  # YAML anchor reference

keda:
  serviceAccount:
    operator:
      annotations:
        eks.amazonaws.com/role-arn: "arn:aws:iam::111111111111:role/keda-my-cluster-dev"
```

## How Values Are Extracted (Git Files Generator)

The ApplicationSet uses a **Matrix Generator** combining:

1. **Cluster Generator** — finds clusters with matching labels
2. **Git Files Generator** — reads and parses the cluster values YAML

```yaml
generators:
  - matrix:
      generators:
        - clusters:
            selector:
              matchLabels:
                datadog: enabled
        - git:
            files:
              - path: "configuration/addons-clusters-values/{{.name}}.yaml"
```

The GoTemplate extracts only the addon-specific section:

```yaml
values: |
  {{- $addonKey := index . "datadog" -}}
  {{- if $addonKey -}}
  {{ $addonKey | toYaml }}
  {{- end -}}
```

**Result**: Each addon Application receives ONLY its config section — no values pollution between addons.

## Value Precedence (lowest to highest)

```
┌─────────────────────────────────────────────┐
│ 1. Helm Chart Defaults                      │
│    (from upstream chart repository)         │
└─────────────────┬───────────────────────────┘
                  │ Overridden by ▼
┌─────────────────────────────────────────────┐
│ 2. Global Values (valueFiles)               │
│    addons-global-values/<addon>.yaml        │
└─────────────────┬───────────────────────────┘
                  │ Overridden by ▼
┌─────────────────────────────────────────────┐
│ 3. Cluster-Specific Values (inline values)  │
│    Git Files generator extracts addon key   │
└─────────────────┬───────────────────────────┘
                  │ Overridden by ▼
┌─────────────────────────────────────────────┐
│ 4. NodePool Config (conditional valueFiles) │
│    Only if eksAutoMode: "true"              │
└─────────────────┬───────────────────────────┘
                  │ Overridden by ▼
┌─────────────────────────────────────────────┐
│ 5. ApplicationSet Parameters (highest)      │
│    Cluster annotations via helper functions │
└─────────────────────────────────────────────┘
```

This follows ArgoCD's Helm values merge order:
1. `valueFiles` (lowest)
2. `values` (inline YAML)
3. `valuesObject`
4. `parameters` (highest)

## Best Practices

**Do:**
- Define global defaults in `addons-global-values/<addon>.yaml`
- Use cluster-specific values only for cluster-unique configs (IAM roles, resources)
- Use YAML anchors in cluster files to avoid duplication
- Use `addons-catalog.yaml` as the single source for addon versions

**Don't:**
- Hardcode values in Helm templates
- Duplicate values across cluster files (use global values)
- Put cluster-specific values in global files
