# MSD Meetup ArgoCD 2023

This project contains the Helm charts necessary for configuring ArgoCD, managing remote clusters, and deploying add-ons across environments using ArgoCD's app-of-apps pattern. All applications, clusters, and their respective configurations are defined in the `values` directory. The project also utilizes ApplicationSet and AppProject CRDs for creating a dynamic application deployment pipeline.

## Directory Structure

```text
msd-meetup-argocd-2023
├── README.md
├── charts
│   ├── argocd-config
│   │   ├── Chart.yaml
│   │   ├── templates
│   │   │   ├── argocd-repo-server.yaml
│   │   │   └── argocd-server.yaml
│   │   └── values.yaml
│   ├── cluster-addons
│   │   ├── Chart.yaml
│   │   ├── templates
│   │   │   ├── addons-app.yaml
│   │   │   ├── apps
│   │   │   │   ├── argocd-config.yaml
│   │   │   │   └── remote-clusters.yaml
│   │   │   └── appsets
│   │   │       └── applicationset.yaml
│   │   └── values.yaml
│   └── clusters
│       ├── Chart.yaml
│       ├── templates
│       │   └── remote-cluster-template.yaml
│       └── values.yaml
└── values
    ├── addons-list.yaml
    ├── clusters.yaml
    └── global.yaml
```
- The `charts` directory contains the Helm charts for the ArgoCD configuration (`argocd-config`), secrets for ArgoCD to connect to remote clusters (`clusters`), and the root app (`cluster-addons`) which manages these two applications.

- The `values` directory contains the configuration for the deployed applications (`addons-list.yaml`), the configuration of the clusters (`clusters.yaml`), and global configuration options (`global.yaml`).

## Technologies Used
- ArgoCD
- Helm
- Kubernetes

## Usage Instructions
Clone the repository and configure the Helm values to fit your needs. Apply the Helm charts in the following order:

1. ArgoCD Configuration
2. Clusters
3. Cluster-Addons

## Setup Instructions
You need to have ArgoCD, Helm, and Kubernetes installed and configured on your machine.
Don't forget to connect your ArgoCD to your repository that will hold this code.

Clone the repository and install the charts as follows:

```bash
git clone https://github.com/moranweissman/msd-meetup-argocd-2023.git
cd msd-meetup-argocd-2023
helm template charts/cluster-addons | kubectl apply -f - -n argocd
```

# Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

License
This project is licensed under the MIT License - see the LICENSE.md file for details.