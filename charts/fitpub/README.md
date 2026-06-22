# FitPub Helm Chart

![FitPub Helm Chart](https://raw.githubusercontent.com/oliinykdm/fitpub-helm/main/docs/banner.png)

FitPub is a federated fitness tracking platform. This chart runs it on Kubernetes. You bring an external PostgreSQL database with PostGIS - the chart wires up everything else.

## Install

From the OCI registry (recommended):

```bash
helm install fitpub oci://ghcr.io/oliinykdm/charts/fitpub --version 0.4.0 -f production-values.yaml
```

Or the classic HTTP repo:

```bash
helm repo add fitpub https://oliinykdm.github.io/fitpub-helm
helm repo update
helm install fitpub fitpub/fitpub -f production-values.yaml
```

Copy and adapt [`examples/production-values.yaml`](https://github.com/oliinykdm/fitpub-helm/blob/main/examples/production-values.yaml)
before running either command.

## Minimal Production Values

```yaml
productionChecks:
  enabled: true

config:
  FITPUB_DATABASE_URL: "jdbc:postgresql://postgres.example.com:5432/fitpub"
  FITPUB_DOMAIN: "fitpub.example.com"
  FITPUB_BASE_URL: "https://fitpub.example.com"
  FITPUB_PUSH_ENABLED: "false"

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

If `FITPUB_PUSH_ENABLED` is set to `"true"`, also provide VAPID public/private keys in the Secret and set `FITPUB_VAPID_SUBJECT`.

## Production Notes

- PostgreSQL **with PostGIS**, not plain PostgreSQL
- `FITPUB_BASE_URL` canonical, no trailing slash
- Push notifications off until VAPID keys and `FITPUB_VAPID_SUBJECT` are set
- One replica unless uploads use `ReadWriteMany` storage (RWO can only mount on one pod)
- Back up the PostGIS database and the uploads PVC
- Use an externally managed Secret for production credentials

## Features

- non-root UID/GID `1001`, restricted Pod Security Standard compliant out of the box
- `readOnlyRootFilesystem` on by default, with emptyDir for `/tmp` and `/app/logs`
- ConfigMap/Secret split for application environment variables
- startup/readiness/liveness probes on `GET /login` (FitPub 1.1.1 compatible)
- CPU/memory limits sized for Java 25, plus a PDB and a preStop drain hook by default
- optional Hikari pool, ActivityPub inbox, mail and feature-toggle config keys
- optional Ingress, HPA, NetworkPolicy and ServiceMonitor
- optional Markdown page mount from an existing Secret
- extension points for extra env, envFrom, volumes, init containers and sidecars

Full docs in the repo:

```text
https://github.com/oliinykdm/fitpub-helm
```

**Mail:** leave the mail `config` keys empty until you set `FITPUB_MAIL_HOST`, then set port/auth/starttls together (see `examples/production-values.yaml`).

**Logs:** the `prod` profile writes rotated files to `/app/logs`, mounted as emptyDir. They survive container restarts but not rescheduling - collect them if you want history.

**ServiceMonitor:** FitPub 1.1.x gates `/actuator/metrics` behind auth, so leave scraping off until actuator access is public or you wire up scrape auth.
