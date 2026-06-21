# Upgrade Notes

## 0.2.7

### New value: `persistence.mountPath`

`persistence.mountPath` (default `/app/uploads`) now controls where the uploads PVC is mounted inside the container. It replaces the previously hardcoded `/app/uploads` path in the Deployment template.

**Action required** only if you set `config.FILE_UPLOAD_DIR` to a non-default path: also set `persistence.mountPath` to the same value, or the chart will now refuse to render with an error explaining the mismatch.

### Validation: `config.FILE_UPLOAD_DIR` must match `persistence.mountPath`

If `persistence.enabled: true` and `config.FILE_UPLOAD_DIR` is set to a different value than `persistence.mountPath`, `helm install` / `helm upgrade` now fails with a descriptive error. Previously, this misconfiguration caused uploads to be written to ephemeral container storage, silently losing all files on pod restart.

### Validation: `config.FITPUB_PAGES_PATH` must match `pages.mountPath`

If `pages.existingSecret` is set and `config.FITPUB_PAGES_PATH` differs from `pages.mountPath`, the chart now fails with a descriptive error. Previously, the pages Secret was mounted at one path while the application read from a different path, resulting in missing pages with no visible error at install time.

### Validation: VAPID keys required when push is enabled (productionChecks)

When `productionChecks.enabled: true` and `config.FITPUB_PUSH_ENABLED: "true"`, the chart now validates that `applicationSecret.data.FITPUB_VAPID_PUBLIC_KEY` is provided (or `applicationSecret.existingSecret` is used). Previously, deploying with push enabled but no VAPID keys was silently accepted, resulting in broken push notifications.

### Validation: ServiceMonitor `scrapeTimeout` must be less than `interval`

If `serviceMonitor.enabled: true` and `scrapeTimeout >= interval`, the chart now fails with a descriptive error. Prometheus rejects this configuration at runtime.

## 0.2.6

New values added in this release. All existing deployments are unaffected — the new knobs default to the same behavior as before.

### New features

- `diagnosticMode` — set `diagnosticMode.enabled=true` to override the container command with `sleep infinity` for interactive debugging.
- `lifecycleHooks` — configure `preStop` / `postStart` hooks. See the Graceful Shutdown section in README for a recommended `preStop` example.
- `command` / `args` — override the container entrypoint without touching the Deployment template.
- `priorityClassName`, `schedulerName`, `runtimeClassName` — scheduling and runtime customization.
- `hostAliases`, `dnsPolicy`, `dnsConfig` — DNS overrides, useful for testing federation with self-hosted instances.
- `commonLabels`, `commonAnnotations` — applied to every resource created by this chart.
- `minReadySeconds` — stability window before a new pod is considered available.

### ServiceMonitor namespaceSelector

The ServiceMonitor now includes `namespaceSelector.matchNames` pointing to the release namespace. If you run Prometheus in a different namespace and previously worked around the missing selector, you can remove the workaround.

### Pod-level automountServiceAccountToken

The Deployment pod spec now explicitly sets `automountServiceAccountToken` from `serviceAccount.automount`. This prevents unintentional token mounts when `serviceAccount.create: false` and the referenced SA has `automountServiceAccountToken: true` at the SA level.

## 0.2.5

### ServiceAccount token automount disabled by default

`serviceAccount.automount` now defaults to `false`. FitPub does not call the Kubernetes API, so mounting a service account token is unnecessary and widens the pod's attack surface.

If you have an external agent that relies on the service account token being present inside the pod, set:

```yaml
serviceAccount:
  automount: true
```

### Health probe initialDelaySeconds removed from readiness and liveness

`readinessProbe.initialDelaySeconds` and `livenessProbe.initialDelaySeconds` have been removed from the default values. `startupProbe` already gates the startup window — adding extra delay on top was causing pods to remain unready or unmonitored for up to 90 seconds after the JVM had already reported healthy.

If you override probes in your values, remove `initialDelaySeconds` from `readinessProbe` and `livenessProbe` to benefit from faster readiness after startup.

### PodDisruptionBudget default changed to maxUnavailable

`podDisruptionBudget.minAvailable` default is now empty. `podDisruptionBudget.maxUnavailable` defaults to `1`.

The old default of `minAvailable: 1` with `replicaCount: 1` (the default) blocked all voluntary pod evictions, preventing node drains. `maxUnavailable: 1` allows drains while still protecting against simultaneous disruptions.

If you need `minAvailable` semantics (for example, with multiple replicas where you must keep at least N healthy), set:

```yaml
podDisruptionBudget:
  enabled: true
  minAvailable: 1
  maxUnavailable: ""
```

### Init container security context hardened

The `volume-permissions` init container now drops all Linux capabilities and only adds back `CHOWN` and `DAC_OVERRIDE`, which are the minimum needed to fix upload directory ownership. `allowPrivilegeEscalation: false` is also now set explicitly.

## 0.2.0

Version `0.2.0` makes the chart more production-oriented and changes how application environment variables are modeled.

### Configuration Split

Non-secret environment variables now live under `config` and are rendered into a ConfigMap.

Secret environment variables now live under `applicationSecret.data` or can be provided through `applicationSecret.existingSecret`.

If you used `config.FITPUB_DATABASE_USERNAME`, `config.FITPUB_DATABASE_PASSWORD` or `config.FITPUB_JWT_SECRET` with `0.1.x`, move them to:

```yaml
applicationSecret:
  data:
    FITPUB_DATABASE_USERNAME: "fitpub"
    FITPUB_DATABASE_PASSWORD: "..."
    FITPUB_JWT_SECRET: "..."
    FITPUB_EMAIL_SECRET: "..."
```

For production, prefer an externally managed Secret:

```yaml
applicationSecret:
  existingSecret: fitpub-secret
```

The existing Secret must contain keys matching the FitPub environment variable names.

### Required Production Settings

Set this in production values:

```yaml
productionChecks:
  enabled: true
```

Production checks fail rendering if required public settings or chart-managed secrets are missing.

`FITPUB_BASE_URL` must not end with a slash. Use `https://example.com`, not `https://example.com/`.

### Runtime Model

The chart remains single-replica by default. `autoscaling.enabled` is available, but multiple replicas should be validated against uploads, background jobs, federation processing and database pool capacity before use.

### PostgreSQL

The chart expects an external PostgreSQL database with PostGIS enabled. It does not install PostgreSQL as a dependency.
