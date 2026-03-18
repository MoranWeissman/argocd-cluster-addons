# Documentation

## Getting Started

| Document | Description |
|----------|-------------|
| [BOOTSTRAP.md](BOOTSTRAP.md) | Step-by-step guide to bootstrap the solution from scratch |
| [VALUES_GUIDE.md](VALUES_GUIDE.md) | How the values hierarchy works — layered configuration, Git Files generator, precedence rules |
| [IAM_SETUP.md](IAM_SETUP.md) | AWS IAM role and IRSA configuration for External Secrets Operator |

## Cloud Providers

| Document | Description |
|----------|-------------|
| [GKE-SETUP.md](GKE-SETUP.md) | GCP/GKE-specific setup — Workload Identity, GCP Secret Manager, Terraform examples |

## Operations

| Document | Description |
|----------|-------------|
| [INFRASTRUCTURE-NODE-SEPARATION.md](INFRASTRUCTURE-NODE-SEPARATION.md) | Isolate infrastructure addons on dedicated Karpenter nodes (EKS Auto Mode) |
| [ARGOCD-ESO-HEALTH-CHECKS.md](ARGOCD-ESO-HEALTH-CHECKS.md) | Fix ESO "Degraded" status in ArgoCD with custom health checks |

## Advanced

| Document | Description |
|----------|-------------|
| [ADDON-MIGRATION.md](ADDON-MIGRATION.md) | Zero-downtime addon adoption when migrating from another ArgoCD instance |
| [MIGRATION-V1-TO-V2.md](MIGRATION-V1-TO-V2.md) | Upgrade guide from V1 to V2 |
