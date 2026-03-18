# ArgoCD Health Checks for External Secrets

## Problem

ArgoCD shows ESO applications as **"Degraded"** even though all resources are healthy. This happens because ArgoCD doesn't have built-in health assessment for ESO Custom Resources.

## Solution

Add custom Lua health checks for ESO CRDs to the `argocd-cm` ConfigMap.

## Configuration

Add to the `argocd-cm` ConfigMap in your ArgoCD namespace:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  resource.customizations.health.external-secrets.io_ClusterSecretStore: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.conditions ~= nil then
        for i, condition in ipairs(obj.status.conditions) do
          if condition.type == "Ready" and condition.status == "False" then
            hs.status = "Degraded"
            hs.message = condition.message
            return hs
          end
          if condition.type == "Ready" and condition.status == "True" then
            hs.status = "Healthy"
            hs.message = condition.message
            return hs
          end
        end
      end
    end
    hs.status = "Progressing"
    hs.message = "Waiting for ClusterSecretStore"
    return hs

  resource.customizations.health.external-secrets.io_ExternalSecret: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.conditions ~= nil then
        for i, condition in ipairs(obj.status.conditions) do
          if condition.type == "Ready" and condition.status == "False" then
            hs.status = "Degraded"
            hs.message = condition.message
            return hs
          end
          if condition.type == "Ready" and condition.status == "True" then
            hs.status = "Healthy"
            hs.message = condition.message
            return hs
          end
        end
      end
    end
    hs.status = "Progressing"
    hs.message = "Waiting for ExternalSecret"
    return hs
```

The same pattern applies to `SecretStore` and `PushSecret` — just change the resource type and message.

## How to Apply

```bash
kubectl patch configmap argocd-cm -n argocd --type merge \
  -p "$(cat argocd-eso-health-checks.yaml)"
```

Then restart the application controller:

```bash
kubectl rollout restart deployment argocd-application-controller -n argocd
```

## Verification

```bash
# Should change from Degraded to Healthy
kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,HEALTH:.status.health.status
```

## References

- [ArgoCD Custom Health Checks](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/#custom-health-checks)
- [External Secrets Status Conditions](https://external-secrets.io/latest/api/externalsecret/)
