# Contributing

Thanks for helping improve the FitPub Helm chart.

## Development Workflow

1. Make focused changes to the chart, examples or documentation.
2. Keep production defaults conservative.
3. Run the local checks:

```bash
helm lint ./charts/fitpub
helm template fitpub ./charts/fitpub
helm template fitpub ./charts/fitpub -f examples/production-values.yaml
helm template fitpub ./charts/fitpub -f examples/development-values.yaml
helm template fitpub ./charts/fitpub -f examples/networkpolicy-smoke-values.yaml
```

Optional: reproduce the CI kind runtime tests locally (requires a reachable cluster and
image pull access):

```bash
# Same shape as .github/workflows/runtime-smoke-test.yaml (kind-runtime job)
kubectl apply -f examples/postgis-dev.yaml
kubectl rollout status deployment/postgis --timeout=180s
kubectl create secret generic fitpub-secret \
  --from-literal=FITPUB_DATABASE_USERNAME=fitpub \
  --from-literal=FITPUB_DATABASE_PASSWORD=fitpub-smoke-test-db-password \
  --from-literal=FITPUB_JWT_SECRET=test-jwt-secret-with-more-than-32-characters \
  --from-literal=FITPUB_EMAIL_SECRET=test-email-secret-with-more-than-32-characters
helm upgrade --install fitpub ./charts/fitpub \
  -f examples/runtime-smoke-values.yaml \
  --wait --timeout 10m
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=fitpub --timeout=600s

# NetworkPolicy smoke (kind-networkpolicy job)
helm uninstall fitpub || true
helm upgrade --install fitpub ./charts/fitpub \
  -f examples/networkpolicy-smoke-values.yaml \
  --wait --timeout 10m
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=fitpub --timeout=600s
```

## Chart Design Principles

- FitPub uses an external PostgreSQL database with PostGIS.
- The default deployment is single-replica.
- Production secrets should normally be managed outside Helm.
- New values should be documented in `values.yaml`, covered by `values.schema.json` when practical and mentioned in README/docs if user-facing.
- Avoid adding dependencies unless they are clearly optional and production-safe.

## Pull Requests

For chart changes, include:

- a summary of the behavior change;
- rendered/tested values' scenario;
- any upgrade notes;
- whether the chart version needs to be bumped.

For release changes, verify the release workflow still supports the first publish to `gh-pages`.
