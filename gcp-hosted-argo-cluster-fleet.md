In this article will demonstrate show you how to manage fleet of clusters and their plugins along with argoCD

This project contains the Helm charts necessary for configuring ArgoCD, <br>
managing remote clusters, and deploying add-ons across environments using ArgoCD's app-of-apps pattern. <br>
All applications, clusters, and their respective configurations are defined in the values directory. <br>
The project also utilizes ApplicationSet and AppProject CRDs for creating a dynamic application deployment pipeline.

### Technologies Used
- external-secrets
- ArgoCD
- Helm
- Kubernetes
- Terraform

### Cloud provider:
- GCP

## Directory Structure

```shell
msd-meetup-argocd-2023
├── charts
│   ├── cluster-addons
│   │   ├── Chart.yaml
│   │   ├── templates
│   │   │   ├── addons-app.yaml
│   │   │   ├── apps
│   │   │   │   └── remote-clusters.yaml
│   │   │   └── appsets
│   │   │       └── applicationset.yaml
│   │   └── values.yaml
│   └── clusters
│       ├── Chart.yaml
│       ├── templates
│       │   └── remote-cluster-template-es.yaml
│       └── values.yaml
├── gcp-hosted-argo-cluster-fleet.md
├── README.md
└── values
    ├── addons-list.yaml
    └── clusters.yaml
```


- `charts` Directory contain the helm templates required for `ArgoCD` to sync items with helm
    - (`argocd-config`) Directory contains the Helm charts for the `ArgoCD` configuration
    - (`clusters`) Directory contains the Helm charts for the ArgoCD `external-secrets` template for `ArgoCD` to connect automatically clusters
    - (`cluster-addons`) Directory contains the Helm charts for the `ArgoCD` to manage plugins


- `values` Directory contains the configuration for the deployed applications 
  - (`addons-list.yaml`) file contains the list of plugins. 
  - (`clusters.yaml`), contains the cluster to be managed 

**Architecture**
```
┌─────────────────────┐          ┌─────────────────────┐         ┌──────────────────────┐          ┌──────────────────────┐   
│Start Manage cluster │ pull     │In you IaC Make sure │         │Apply Configuration   │    2     │By this point the     │
│plugin with ArgoCD   │ secret   │You save the GCP CA  │ create  │with kubectl so argoCD│   Push   │Cluster should be     │
│By add cluster name  ├ with ES  │In The Global Secret ├────────►│Start to sync your    │◄──────── │Added to you cluster  │
│ti the file:         │◄─────────│Manager.             │◄────────┤cluster.              │          ┤fleet.                │
│/values/clusters.yaml│          │                     │ result  │                      │          │                      │
└─────────────────────┘          └─────────────────────┘         └──────────────────────┘          └──────────────────────┘
```


***GCP Prerequisites***
For this lab you will need to create 2 GCP projects. <br>
- project will represent where ArgoCD external-secrets CRD are installed. 
- project that will represent a cluster that should be added to Argo.
- Create service account for external-secrets. 
- Create service account for ArgoCD to enable workload-identity.

***Global Environment Variables***
```shell
ARGO_PROJECT="argo-project"                     ## External-Secrets and argoCD installed here
HOSTED_CLUSTER_PROJECT="development-sandbox"    ## Joined to Argo fleet
EXTERNAL_SECRETS_SA_NAME="external-secrets"     ## Installed on $ARGO_PROJECT
ARGO_SA_NAME="argocd"                           ## Installed on $ARGO_PROJECT
ARGO_NAMESPACE="argocd"                         ## The namespace of Argo     
EXTERNAL_SECRETS_NAMESPACE="external-secrets"   ## The namespace of external secrets
EXTERNAL_SECRETS_K8S_SA_NAME="external-secrets" ## Tha name of the service account inside k8s
```

You also need to create hosted cluster master authorized network to listen to ArgoCD NAT gateway. <br>
```shell
curl ifconfig.me                                ## Outputs the IP address of the NAT, Run this in the Argo server pod
```

**You need to allow workload identity in your both clusters.**
I used terraform to achieve it.

*** It's recommended to use IaC instead.

After that you can run the following command:
```shell
#!/bin/bash

projects=("$ARGO_PROJECT")
service_account_to_grant=("$EXTERNAL_SECRETS_SA_NAME")
namespace_to_delegate="$EXTERNAL_SECRETS_NAMESPACE" 
k8s_service_account_to_delegate="external-secrets"
roles=("secretmanager.secretAccessor" "iam.serviceAccountTokenCreator")

if [[ -z "${projects}" ]]; then
  echo "projects cannot be empty"
  exit 1
fi

if [[ -z "${service_account_to_grant}" ]]; then
  echo "service_account_to_grant cannot be empty"
  exit 1
fi

for project in "${projects[@]}"; do
  for sa in "${service_account_to_grant[@]}"; do
    gcloud iam service-accounts add-iam-policy-binding "${service_account_to_grant}" \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:$project.svc.id.goog[$namespace_to_delegate/$k8s_service_account_to_delegate]" \
    --project "${project}"

    for role in "${roles[@]}"; do
      gcloud service-accounts add-iam-policy-binding \
      "${service_account_to_grant}@${project}.iam.gserviceaccount.com" \
      --project "${project}" \
      --member=serviceAccount:"${service_account_to_grant}" \
      --role=roles/"${role}"
    done
  done
done
```

This will grant external secrets the ability to pull secrets.

Install the external secrets in you cluster:

```shell
helm repo add external-secrets https://charts.external-secrets.io

helm upgrade -i external-secrets external-secrets/external-secrets \
--set serviceAccount.name=$EXTERNAL_SECRETS_K8S_SA_NAME \
--set serviceAccount.annotations.iam\.gke\.io/gcp-service-account="$EXTERNAL_SECRETS_SA_NAME@$ARGO_PROJECT.iam.gserviceaccount.com" \
-n external-secrets \
--create-namespace
```

In this point you should be able to pull secrets from the secret manager.



I'm using Terraform to store the details of the cluster relevant for authenticate to the cluster.

Here is the block:
```hcl
locals {
  ARGO_PROJECT="argo-project"

}

data "google_client_config" "current" {}

data "google_container_cluster" "cluster" {
  name     = var.cluster_name                                                                 # The cluster name that should be joined to ArgoCD
  location = var.region                                                                       # The cluster region that should be joined to ArgoCD
  project  = var.project_id                                                                   # The cluster project that should be joined to ArgoCD
}

resource "google_secret_manager_secret" "gke-secret" {
  project = local.ARGO_PROJECT                                                                # Store the secret in Argo Project
  secret_id = ""                                                                              # Put here the name of the cluster as the name of the secret
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "gke-secret-values" {
  secret = google_secret_manager_secret.gke-secret.id
  secret_data =  jsonencode(
    {
      "caData": data.google_container_cluster.cluster.master_auth.0.cluster_ca_certificate,    # The cluster CA that should be joined to ArgoCD must be encoded
      "host": "https://${data.google_container_cluster.cluster.endpoint}",                     # The cluster endpoint (Address) that should be joined to ArgoCD
      "clusterName": data.google_container_cluster.cluster.name                                # The cluster project that should be joined to ArgoCD
    }
  )
}
```


Finally, 
Add the cluster to Argo:
helm template charts/cluster-addons -f values/addons-list.yaml | kubectl create -f - -n argo --dry-run=client -o yaml | kubectl apply -f - -n argo


