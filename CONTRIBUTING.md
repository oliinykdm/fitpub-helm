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
