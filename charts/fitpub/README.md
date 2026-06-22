# FitPub Helm Chart

![FitPub Helm Chart](https://raw.githubusercontent.com/oliinykdm/fitpub-helm/main/docs/banner.png)

FitPub is a federated fitness tracking platform. This chart deploys the FitPub application on Kubernetes and expects an external PostgreSQL database with PostGIS enabled.

## Install

```bash
helm repo add fitpub https://oliinykdm.github.io/fitpub-helm
helm repo update
helm install fitpub fitpub/fitpub -f production-values.yaml
```

## Minimal Production Values

```yaml
productionChecks:
  enabled: true

config:
  FITPUB_DATABASE_URL: "jdbc:postgresql://postgres.example.com:5432/fitpub"
  FITPUB_DOMAIN: "fitpub.example.com"
  FITPUB_BASE_URL: "https://fitpub.example.com"

applicationSecret:
  existingSecret: fitpub-secret

ingress:
  enabled: true
  className: traefik
  hosts:
    - host: fitpub.example.com
      paths:
        - path: /
          pathType: Prefix
```

The referenced Secret must contain:

- `FITPUB_DATABASE_USERNAME`
- `FITPUB_DATABASE_PASSWORD`
- `FITPUB_JWT_SECRET`
- `FITPUB_EMAIL_SECRET`

## Production Notes

- Use PostgreSQL with PostGIS, not plain PostgreSQL.
- Keep `FITPUB_BASE_URL` canonical and without a trailing slash.
- Keep `replicaCount: 1` until uploads, background jobs and federation processing have been validated for multiple pods.
- Back up the external PostGIS database and the uploads PVC.
- Use an externally managed Secret for production credentials.

## Features

- non-root runtime security context for UID/GID `1001`
- ConfigMap/Secret split for application environment variables
- optional Ingress, HPA, PDB, NetworkPolicy and ServiceMonitor resources
- optional Markdown page mount from an existing Secret
- extension points for extra env, envFrom, volumes, init containers and sidecars

Full documentation is available in the chart repository:

```text
https://github.com/oliinykdm/fitpub-helm
```
