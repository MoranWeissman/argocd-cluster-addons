# Contributing

Contributions are welcome! Here's how to help.

## How to Contribute

1. **Fork** the repository
2. **Create a branch** for your feature or fix
3. **Make your changes** following the patterns below
4. **Test** your changes (see Testing section)
5. **Submit a pull request** with a clear description

## Adding a New Addon

1. Add the addon entry to `configuration/addons-catalog.yaml`
2. Create global default values at `configuration/addons-global-values/<addon>.yaml`
3. If using EKS Auto Mode, create nodepool config at `configuration/addons-global-values/nodepools-config-values/<addon>-nodepool-config.yaml`
4. Add an example cluster override in `configuration/addons-clusters-values/my-app-dev.yaml`
5. Update the Supported Addons table in `README.md`

## Guidelines

- **Use public Helm chart repos only** — no internal/private chart repositories
- **Sanitize all examples** — use placeholder values (`111111111111`, `<your-org>`, `example.com`)
- **Follow existing patterns** — look at how Datadog or KEDA are configured as reference
- **One addon per PR** — makes review easier
- **Update docs** if your change affects configuration or architecture

## Testing

Before submitting, verify your templates render correctly:

```bash
# Lint the bootstrap chart
helm lint bootstrap/ \
  -f configuration/bootstrap-config.yaml \
  -f configuration/addons-catalog.yaml \
  -f configuration/cluster-addons.yaml \
  -f configuration/datadog-project-mappings.yaml

# Template the bootstrap chart
helm template cluster-addons-bootstrap bootstrap/ \
  -f configuration/bootstrap-config.yaml \
  -f configuration/addons-catalog.yaml \
  -f configuration/cluster-addons.yaml \
  -f configuration/datadog-project-mappings.yaml
```

## Reporting Issues

Open an issue with:
- What you expected
- What happened
- Your ArgoCD version
- Relevant logs or Application status
