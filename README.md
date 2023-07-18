# MSD Meetup ArgoCD 2023

This repository contains the configurations and templates for deploying cluster addons with ArgoCD ApplicationSets.

## Directory Structure

```text
msd-meetup-argocd-2023
├── argocd
│   ├── apps
│   │   └── argocd-config.yaml
│   └── argocd-config
│       ├── argocd-repo-server.yaml
│       └── argocd-server.yaml
├── cluster-addons
│   ├── appset-template
│   │   ├── templates
│   │   │   └── appset-template.yaml
│   │   ├── chart.yaml
│   │   └── values.yaml
│   ├── templates
│   │   ├── app-template.yaml
│   │   └── cluster-addons-root.yaml
│   ├── values
│   │   ├── cluster-addons-appsets
│   │   │   ├── msd-chicken.yaml
│   │   │   └── msd-cow.yaml
│   │   └── cluster-addons-apps.yaml
│   ├── chart.yaml
│   └── values.yaml
└── remote-clusters
    ├── yamls
    └── remote-clusters.yaml
```
# argocd

The `argocd` directory contains configurations for ArgoCD, including `argocd-config.yaml` for application configuration and `argocd-repo-server.yaml` and `argocd-server.yaml` for ArgoCD server configuration.

# cluster-addons

The `cluster-addons` directory contains the templates and values files for the addons.

- The `appset-template` subdirectory contains Helm chart for managing cluster addons application sets and projects.
- The `templates` subdirectory contains application templates and root configuration.
- The `values` subdirectory contains values for each addon. `cluster-addons-appsets` further categorizes values for each addon into `msd-chicken.yaml` and `msd-cow.yaml`.

# remote-clusters

The `remote-clusters` directory contains configuration for remote clusters in `remote-clusters.yaml`. The `yamls` subdirectory is currently empty but can be used for additional configurations.

# Naming Conventions

The naming convention is `verb-noun.yaml`, which helps describe the purpose of each file. The names are descriptive and adhere to the following examples:

- `argocd-config.yaml`: Configuration for ArgoCD.
- `app-template.yaml`: Template for an application.
- `cluster-addons-root.yaml`: Root configuration for cluster addons.

# Contributing

Please follow the existing structure and naming conventions when adding new files or making changes to existing ones. If you have suggestions for improvements or changes, please open an issue for discussion.
