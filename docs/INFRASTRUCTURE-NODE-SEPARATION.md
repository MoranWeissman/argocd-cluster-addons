# Infrastructure Node Separation with Karpenter

## Overview

This solution supports isolating critical cluster infrastructure components (Datadog, External Secrets, Istio, etc.) from business logic applications by running them on dedicated Karpenter-managed node pools.

This feature is designed for **EKS Auto Mode** clusters.

## Problem Statement

Without node separation:
- Infrastructure components compete for resources with business applications
- No isolation between critical platform services and product workloads
- Difficult to guarantee resource availability for essential components
- Cannot apply different scaling or reliability policies per workload type

With node separation:
- Infrastructure runs on dedicated Karpenter-managed nodes
- Complete isolation via taints and tolerations
- Guaranteed resource availability for platform services
- Independent scaling and lifecycle management

## Architecture

```
┌───────────────────────────────────────────────────────────────┐
│ EKS Auto Mode Cluster                                         │
│                                                               │
│  ┌──────────────────────────┐  ┌───────────────────────────┐  │
│  │  Infrastructure Nodes    │  │  Application Nodes        │  │
│  │  (infra-karpenter)       │  │  (Managed by product team)│  │
│  │                          │  │                           │  │
│  │  - Datadog Agents        │  │  - Business Logic Apps    │  │
│  │  - ESO Controller        │  │  - Product Workloads      │  │
│  │  - Istio Control Plane   │  │                           │  │
│  │  - KEDA Operator         │  │                           │  │
│  │  - Kyverno               │  │                           │  │
│  │                          │  │                           │  │
│  │  Taint: infrastructure   │  │  No infrastructure taint  │  │
│  │  Label: node-type=infra  │  │                           │  │
│  └──────────────────────────┘  └───────────────────────────┘  │
└───────────────────────────────────────────────────────────────┘
```

## How It Works

### 1. Karpenter NodePool

When a cluster has label `eksAutoMode: "true"`, a dedicated ApplicationSet (sync wave -2) deploys a Karpenter NodePool **before** any addons.

The NodePool is defined in `configuration/karpenter-nodepools-config.yaml`:
- **Label**: `node-type: infrastructure`
- **Taint**: `infrastructure=true:NoSchedule`
- **Instance types**: Compute (c), general (m), memory (r) optimized
- **Consolidation**: Automatic right-sizing every 30s
- **Node expiry**: 14 days (for security patching)

### 2. Automatic Addon Integration

The ApplicationSet template automatically loads infrastructure node overrides when `eksAutoMode: "true"`:

```yaml
# From bootstrap/templates/addons-appset.yaml
valueFiles:
  - '$values/configuration/addons-global-values/<addon>.yaml'
  # Automatically loaded when eksAutoMode is "true":
  - '$values/configuration/addons-global-values/nodepools-config-values/<addon>-nodepool-config.yaml'
```

Each override file adds `nodeSelector` and `tolerations` so addon pods schedule on infrastructure nodes.

### 3. Pre-configured Addons

Override files exist for all supported addons in `configuration/addons-global-values/nodepools-config-values/`:

| Addon | nodeSelector | Toleration | Notes |
|-------|-------------|------------|-------|
| Datadog (clusterAgent) | `node-type: infrastructure` | `infrastructure=true:NoSchedule` | |
| Datadog (agents DaemonSet) | None (runs on ALL nodes) | `infrastructure=true:NoSchedule` | Exception: collects from every node |
| External Secrets | `node-type: infrastructure` | `infrastructure=true:NoSchedule` | |
| Istiod | `node-type: infrastructure` | `infrastructure=true:NoSchedule` | |
| Istio CNI | `node-type: infrastructure` | `infrastructure=true:NoSchedule` | |
| Istio Ingress | `node-type: infrastructure` | `infrastructure=true:NoSchedule` | |
| KEDA | `node-type: infrastructure` | `infrastructure=true:NoSchedule` | Operator + metrics server + webhooks |
| Kyverno | `node-type: infrastructure` | `infrastructure=true:NoSchedule` | |
| Cert Manager | `node-type: infrastructure` | `infrastructure=true:NoSchedule` | |
| Argo Rollouts | `node-type: infrastructure` | `infrastructure=true:NoSchedule` | |
| Argo Workflows | `node-type: infrastructure` | `infrastructure=true:NoSchedule` | |
| Argo Events | `node-type: infrastructure` | `infrastructure=true:NoSchedule` | |
| External DNS | `node-type: infrastructure` | `infrastructure=true:NoSchedule` | |
| Secrets Store CSI Driver | `node-type: infrastructure` | `infrastructure=true:NoSchedule` | |
| SSCDP AWS | `node-type: infrastructure` | `infrastructure=true:NoSchedule` | |

## Enablement

### 1. Enable on Cluster

Add the `eksAutoMode` label:

```yaml
# configuration/cluster-addons.yaml
clusters:
  - name: my-cluster-dev
    labels:
      eksAutoMode: "true"    # Enables infrastructure NodePool
      datadog: enabled
      keda: enabled
      # ... other addons
```

### 2. Verify NodePool

```bash
kubectl get nodepool
# NAME                       NODECLASS   NODES   READY
# infra-karpenter-nodepool   default     2       True
```

### 3. Verify Nodes

```bash
kubectl get nodes -l node-type=infrastructure
```

### 4. Verify Pod Scheduling

```bash
# Infrastructure pods should be on infrastructure nodes
kubectl get pods -n datadog -o wide
kubectl get pods -n external-secrets -o wide
kubectl get pods -n istio-system -o wide
```

## Resource Management

**All infrastructure components MUST define resource requests and limits.**

Karpenter sizes nodes based on pod resource requests. Without them, Karpenter provisions undersized nodes leading to CPU/memory exhaustion.

The global addon values files (`configuration/addons-global-values/<addon>.yaml`) already include sensible defaults. Override per-cluster if needed.

## Cost Optimization

The NodePool is configured for automatic cost optimization:

- **Consolidation**: `WhenEmptyOrUnderutilized` with 30s check interval
- **Empty nodes**: Removed immediately
- **Underutilized nodes**: Automatically right-sized
- **Resource limits**: Max 10 nodes, 1000 CPU, 1000Gi memory (configurable)

## Adding a New Addon to Infrastructure Nodes

1. Create override file:

```yaml
# configuration/addons-global-values/nodepools-config-values/<addon>-nodepool-config.yaml
controller:
  nodeSelector:
    node-type: infrastructure
  tolerations:
    - key: infrastructure
      operator: Equal
      value: "true"
      effect: NoSchedule
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      memory: 256Mi
```

2. Enable both labels on the cluster — the ApplicationSet handles the rest automatically.

## Limitations

- **EKS Auto Mode only**: Requires Karpenter v1 (included in Auto Mode)
- **Not for applications**: Infrastructure nodes are for platform services only
- **Max 10 nodes**: Default limit, configurable in `karpenter-nodepools-config.yaml`
