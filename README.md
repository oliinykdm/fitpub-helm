# Fitpub Helm Chart

[![Lint](https://github.com/oliinykdm/fitpub-helm/actions/workflows/helm-lint.yaml/badge.svg)](https://github.com/oliinykdm/fitpub-helm/actions/workflows/helm-lint.yaml)

Helm chart for deploying [Fitpub](https://codeberg.org/fitpub/fitpub) — a federated fitness tracking platform.

> **Status:** Work in progress. The chart is being actively developed and tested.

## Features

- Deployment with proper security context (runs as non-root user 1001)
- PersistentVolumeClaim for user uploads (`/app/uploads`)
- Init container to set correct permissions on the volume
- Readiness and Liveness probes (`/actuator/health`)
- Dynamic configuration via `config` section (injected as environment variables)
- Support for external PostgreSQL database

## Prerequisites

- Kubernetes 1.21+
- Helm 3.8+

## Installation

```bash
helm repo add fitpub https://oliinykdm.github.io/fitpub-helm
helm install fitpub fitpub/fitpub
```

Or install directly from the repository:

```bash
git clone https://github.com/oliinykdm/fitpub-helm.git
cd fitpub-helm
helm install fitpub ./charts/fitpub
```

## Configuration

Most configuration is done through the `config` section in `values.yaml`. All values from this section are passed to the container as environment variables.

Example of important settings:

```yaml
config:
  FITPUB_DATABASE_URL: "jdbc:postgresql://postgres:5432/fitpub"
  FITPUB_DATABASE_USERNAME: "fitpub"
  FITPUB_DATABASE_PASSWORD: "your-password"

  FITPUB_DOMAIN: "your-domain.com"
  FITPUB_BASE_URL: "https://your-domain.com"

  FITPUB_JWT_SECRET: "your-super-secret-key"
```

See [values.yaml](charts/fitpub/values.yaml) for the full list of available options.

## Persistence

By default, the chart creates a `PersistentVolumeClaim` for storing user uploads at `/app/uploads`.

You can customize storage size and class:

```yaml
persistence:
  enabled: true
  storageClass: ""
  size: 5Gi
```

## Upgrading

```bash
helm upgrade fitpub fitpub/fitpub
```

## Related Links

- Fitpub project: https://codeberg.org/fitpub/fitpub
- Original Kubernetes manifests discussion: https://codeberg.org/fitpub/fitpub/issues/301
- This chart repository: https://github.com/oliinykdm/fitpub-helm

## Contributing

This chart is currently maintained in a personal repository. Once it reaches a stable state, it will be proposed to the upstream Fitpub project on Codeberg.

Feel free to open issues or pull requests with improvements.
