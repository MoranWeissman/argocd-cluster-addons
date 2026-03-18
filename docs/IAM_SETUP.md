# IAM Setup for External Secrets Operator (AWS)

How to configure IAM roles for ESO to access AWS Secrets Manager via IRSA.

## Overview

ESO uses **IRSA (IAM Roles for Service Accounts)** to authenticate with AWS:
1. EKS cluster has an OIDC provider
2. IAM role trusts the OIDC provider
3. ESO service account assumes the IAM role

## Step 1: Get Your Cluster's OIDC Provider ID

```bash
aws eks describe-cluster \
  --name <your-cluster-name> \
  --region <your-region> \
  --query 'cluster.identity.oidc.issuer' \
  --output text

# Example output: https://oidc.eks.eu-west-1.amazonaws.com/id/ABCDEF1234567890
# Extract the ID: ABCDEF1234567890
```

## Step 2: Create IAM Role with Trust Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/oidc.eks.<REGION>.amazonaws.com/id/<OIDC_ID>"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.<REGION>.amazonaws.com/id/<OIDC_ID>:sub": "system:serviceaccount:external-secrets:external-secrets",
          "oidc.eks.<REGION>.amazonaws.com/id/<OIDC_ID>:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

Replace `<ACCOUNT_ID>`, `<REGION>`, and `<OIDC_ID>` with your values.

## Step 3: Attach Permissions Policy

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
        "arn:aws:secretsmanager:*:*:secret:k8s-*",
        "arn:aws:secretsmanager:*:*:secret:datadog-api-keys-integration*",
        "arn:aws:secretsmanager:*:*:secret:argocd/*"
      ]
    }
  ]
}
```

Adjust the resource patterns to match your secret naming conventions.

## Step 4: Configure Bootstrap

Set the role ARN in `configuration/bootstrap-config.yaml`:

```yaml
bootstrap:
  eso:
    serviceaccount:
      name: external-secrets
      roleArn: "arn:aws:iam::<ACCOUNT_ID>:role/<YOUR_ESO_ROLE_NAME>"
```

## Adding ESO to Remote Clusters

Each remote cluster that runs ESO as a managed addon also needs an IAM role.

The role ARN is injected automatically by the `eso.valuesObject` helper in the ApplicationSet template using the convention:
```
arn:aws:iam::<accountId>:role/EKS-ESO-<clusterName>
```

Override per-cluster in the cluster values file if your naming convention differs:
```yaml
# configuration/addons-clusters-values/my-cluster.yaml
external-secrets:
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: "arn:aws:iam::111111111111:role/my-custom-eso-role"
```

## Troubleshooting

### ESO Cannot Assume Role

1. Verify OIDC provider exists:
   ```bash
   aws iam list-open-id-connect-providers
   ```

2. Verify service account annotation:
   ```bash
   kubectl get sa external-secrets -n external-secrets -o yaml
   ```

3. Verify trust policy includes your cluster's OIDC ID

4. Check ESO logs:
   ```bash
   kubectl logs -n external-secrets deployment/external-secrets
   ```

### OIDC Provider Not Registered

```bash
OIDC_ISSUER=$(aws eks describe-cluster --name <cluster> --region <region> --query 'cluster.identity.oidc.issuer' --output text)

aws iam create-open-id-connect-provider \
  --url $OIDC_ISSUER \
  --client-id-list sts.amazonaws.com
```

## Security Best Practices

- **Least privilege**: Only grant access to secrets ESO needs
- **Audit**: Enable CloudTrail for Secrets Manager access
- **Rotation**: Regularly rotate secrets
- **Scoping**: Use specific resource ARN patterns, not `*`
