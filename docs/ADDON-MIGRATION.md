# Addon Migration Guide (Zero-Downtime Adoption)

This guide explains how to migrate addons from an existing ArgoCD instance to this solution without service disruption. This is an **optional advanced feature** — skip this if you're deploying addons fresh.

## When Do You Need This?

- You have addons already running on clusters, managed by another ArgoCD instance
- You want this solution to take ownership without pod restarts or resource deletion
- You need zero-downtime migration

## How It Works

The `inMigration` flag in `addons-catalog.yaml` injects `ignoreDifferences` rules into the Application. These rules tell ArgoCD to ignore pod template differences during adoption, preventing restarts.

```yaml
# configuration/addons-catalog.yaml
applicationsets:
  - appName: istiod
    repoURL: https://istio-release.storage.googleapis.com/charts
    chart: istiod
    version: 1.28.0
    namespace: istio-system
    inMigration: true  # ← Enables migration protection
```

The `migrationIgnoreDifferences` block (at the bottom of `addons-catalog.yaml`) defines what to ignore:
- Deployment pod templates
- StatefulSet pod templates
- DaemonSet pod templates
- Job/CronJob pod templates

## Prerequisites

### OLD ArgoCD Instance

The OLD ArgoCD ApplicationSet must be configured to allow safe Application deletion without destroying cluster resources:

1. **`syncPolicy.preserveResourcesOnDeletion: true`** (ApplicationSet level)
   - When an Application is removed, resources remain in the cluster

2. **`prune: false`** (Application template)
   - Prevents deleting resources that exist in cluster but not in Git

3. **No finalizers** (Application template)
   - Allows Applications to be deleted immediately without resource cleanup

Without these settings on the OLD side, removing an Application will delete its resources.

### NEW ArgoCD Instance (This Solution)

Already configured:
- `prune: true` in ApplicationSet (normal operation after migration)
- `inMigration` flag support in the ApplicationSet template
- `migrationIgnoreDifferences` defined in `addons-catalog.yaml`

## Migration Process

### Step 1: Enable Migration Mode

Set `inMigration: true` on the addon in `configuration/addons-catalog.yaml`:

```yaml
applicationsets:
  - appName: istiod
    repoURL: https://istio-release.storage.googleapis.com/charts
    chart: istiod
    version: 1.28.0
    namespace: istio-system
    inMigration: true
```

### Step 2: Configure Values

Ensure values match the OLD ArgoCD configuration exactly — no diffs allowed.

1. Set global defaults in `configuration/addons-global-values/<addon>.yaml`
2. Set per-cluster overrides in `configuration/addons-clusters-values/<cluster>.yaml`
3. Enable the addon on the cluster in `configuration/cluster-addons.yaml`:

```yaml
clusters:
  - name: target-cluster
    labels:
      istiod: enabled
```

Commit and push.

### Step 3: Verify Application Created

In the NEW ArgoCD UI:
- Navigate to Applications
- Find the addon application
- Status may show `Synced` (auto-sync reconciled) or `OutOfSync` (both are normal)

At this point, TWO ArgoCD instances are watching the same resources — this is expected and safe.

### Step 4: Remove Addon from OLD ArgoCD

In the OLD ArgoCD repository, remove the addon label from the cluster:

```yaml
clusters:
  - name: target-cluster
    labels:
      # istiod: enabled    # ← Commented out
      datadog: enabled      # Other addons remain
```

Commit, create PR, and merge.

### Step 5: Verify Resources Survived

After the OLD ArgoCD removes its Application:

```bash
# Resources should still be running
kubectl get deployment istiod -n istio-system
kubectl get pods -n istio-system
# Expected: All running, no restarts
```

### Step 6: Verify NEW ArgoCD Ownership

In the NEW ArgoCD UI:
1. Find the Application
2. If already `Synced + Healthy` — done
3. If `OutOfSync` — click **Refresh > Hard Refresh**, wait for auto-sync

```bash
# Verify no pod restarts
kubectl get pods -n istio-system -o wide
# AGE should match pre-migration (no restarts)
```

### Step 7: Disable Migration Mode

After the addon is verified healthy (recommended: wait 24-48 hours):

```yaml
applicationsets:
  - appName: istiod
    repoURL: https://istio-release.storage.googleapis.com/charts
    chart: istiod
    version: 1.28.0
    namespace: istio-system
    # inMigration: removed or set to false
```

This removes the `ignoreDifferences` rules so ArgoCD enforces full drift detection going forward.

## Removing inMigration Entirely

If you're not migrating from another ArgoCD instance and don't need this feature at all, you can safely:

1. Ensure no addons have `inMigration: true` in `addons-catalog.yaml`
2. Optionally remove the `migrationIgnoreDifferences` block from `addons-catalog.yaml`
3. Optionally remove the `inMigration` conditional block from `bootstrap/templates/addons-appset.yaml` (lines referencing `$appset.inMigration`)

The feature is dormant when no addons set `inMigration: true` — it adds zero overhead.

## Best Practices

1. **Migrate one addon at a time** per cluster — easier to troubleshoot
2. **Values must match exactly** — any diff will cause resource updates
3. **Keep migration mode short** — `inMigration` disables drift detection for pod templates
4. **Verify before disabling** — confirm `Synced + Healthy` with no restarts before removing `inMigration`

## Troubleshooting

### Application Stuck OutOfSync After Removing from OLD ArgoCD

Try hard refresh 2-3 times (wait 10-15 seconds between attempts).

If still stuck, remove old ArgoCD tracking annotations:
```bash
kubectl annotate deployment <name> -n <namespace> \
  argocd.argoproj.io/tracking-id- \
  argocd.argoproj.io/instance-
```

Then hard refresh again.

### Pod Restarts After Migration

This means values don't match. Check:
- Global values in `addons-global-values/<addon>.yaml`
- Cluster-specific values in `addons-clusters-values/<cluster>.yaml`
- Compare rendered manifests between OLD and NEW ArgoCD
