# Upgrade Notes

## 0.3.7

### Mail defaults no longer forced without a host

The chart no longer renders `FITPUB_MAIL_PORT`, SMTP auth, or STARTTLS settings into
the ConfigMap unless you set them explicitly. Previously, empty `FITPUB_MAIL_HOST`
combined with port `587` and forced auth could make FitPub talk to `localhost:587`
instead of the application default `localhost:25`.

**Action required:** if you relied on chart defaults for SMTP, add mail settings to
your values when `FITPUB_MAIL_HOST` is set — see
[`examples/production-values.yaml`](../examples/production-values.yaml).

### Optional config keys for pool, federation and feature toggles

`values.yaml` now documents (empty by default) Hikari pool settings
(`FITPUB_DB_*`), ActivityPub inbox tuning (`FITPUB_ACTIVITYPUB_*`,
`FITPUB_REMOTE_ACTIVITY_BACKFILL`), `FITPUB_MAIL_PROTOCOL`, `FITPUB_OSM_TILES_ENABLED`
and `FITPUB_WEATHER_ENABLED`. Empty values are omitted from the ConfigMap.

### ReadWriteOnce scaling and RollingUpdate validation

Render now fails when `persistence.accessMode=ReadWriteOnce` and either:

- `replicaCount > 1`, or
- `autoscaling.maxReplicas > 1`, or
- `deploymentStrategy.type=RollingUpdate`

This applies to chart-managed PVCs **and** `persistence.existingClaim`. Use
`ReadWriteMany` for multi-pod uploads, or keep a single replica with `Recreate`.

### CI: NetworkPolicy smoke test

The runtime workflow includes a second job that installs with
`examples/networkpolicy-smoke-values.yaml` and verifies the pod becomes Ready under
restricted egress.

## 0.3.6

### Memory request aligned with limit

Default `resources.requests.memory` is now **3072Mi**, matching `resources.limits.memory`.
Java 25 uses `-XX:MaxRAMPercentage=75` against the **limit**, so a lower request
(2048Mi in 0.3.5) could schedule the pod on a node without enough RAM for the
calculated heap plus native overhead.

**Action required** only if you tuned requests down manually — raise them again or
lower `MaxRAMPercentage` via `JAVA_TOOL_OPTIONS`.

### ConfigMap omits empty `config` values

Non-empty `config` keys are rendered into the ConfigMap; empty strings are skipped.
This lets Spring Boot fall back to application defaults (for example `FITPUB_MAIL_HOST`
defaults to `localhost` when unset). Explicit non-empty values in your values file
behave as before.

### NetworkPolicy ingress validation

`helm install`/`helm upgrade` now fails when `networkPolicy.enabled=true`,
`networkPolicy.ingress.enabled=false`, and `networkPolicy.ingress.extraRules` is
empty. That combination denies all inbound traffic to FitPub.

### Dev and smoke example resources

`examples/development-values.yaml` and `examples/runtime-smoke-values.yaml` now
use **1536Mi** request/limit and `JAVA_TOOL_OPTIONS=-XX:MaxRAMPercentage=60` for
kind/minikube-sized nodes.

### Documentation fixes

Quickstart verification uses a `curlimages/curl` pod (the FitPub **1.1.1** JRE
image does not ship `curl`). Troubleshooting commands use label selectors instead
of assuming the Deployment is always named `fitpub`.

## 0.3.5

### Default memory raised for Java 25

Default `resources.requests.memory` is now **2048Mi** (CPU request **250m**) and
`resources.limits.memory` is **3072Mi**. The FitPub image sets
`-XX:MaxRAMPercentage=75`, so a 2048Mi limit leaves too little headroom for heap
plus metaspace and native memory on Java 25.

Throwaway clusters can keep lower values — see `examples/development-values.yaml`
and `examples/runtime-smoke-values.yaml`.

### Stronger inline secret validation

When `productionChecks.enabled=true` and Helm manages the Secret inline, the
chart now also rejects trivial `FITPUB_DATABASE_PASSWORD` values (shorter than
12 characters or obvious placeholders such as `fitpub`, `replace-me`, `password`).

JWT and email secrets now fail on common placeholder substrings such as
`replace-me` / `replace-with`, not only on an exact known-value list.

**Action required** if you copied placeholder passwords from older examples —
generate real values (`openssl rand -base64 24` for the database password).

### HPA — zero utilization targets

HPA metric rendering and validation now treat `0` as an explicitly set CPU or
memory target (same `toString` approach as the PDB fix in 0.2.8).

### Install notes and documentation

- `NOTES.txt` warns when `FITPUB_DATABASE_URL` is empty or when
  `productionChecks` is enabled with `applicationSecret.existingSecret`.
- README NetworkPolicy example includes HTTPS **443** egress for federation.
- ServiceMonitor docs now state that FitPub 1.1.x requires authentication for
  `/actuator/metrics` unless the app image changes.
- `icon.png` is published at the repository root for Artifact Hub.

## 0.3.4

### Default probes → `GET /login`

FitPub **1.1.1** (and other 1.1.x images without a public actuator health endpoint)
returns HTTP **302/403** on `/actuator/health/**` because Spring Security requires
authentication. Kubelet treats **302 as success**, so actuator-based probes could
mark the pod Ready before the application finished starting.

The chart now probes **`GET /login`** (permitAll, HTTP **200**) for startup,
readiness and liveness. This matches FitPub **1.1.1** behaviour and makes
`helm install --wait` reliable.

When you deploy a FitPub release that permits unauthenticated
`/actuator/health/**`, override probes back to the split actuator paths — see
[docs/troubleshooting.md](troubleshooting.md).

### ServiceMonitor default path → `/actuator/metrics`

The default `serviceMonitor.path` is now `/actuator/metrics`, which the prod Spring
profile exposes. `/actuator/prometheus` is not available unless
`micrometer-registry-prometheus` is added to the FitPub image. If you overrode the
path explicitly, no change is required.

### NetworkPolicy egress validation

`helm install`/`helm upgrade` now fails when `networkPolicy.enabled=true`,
`networkPolicy.egress.allowAll=false`, and `networkPolicy.egress.extraRules` is
empty. That combination creates a policy with `policyTypes: [Egress]` but no
allow rules, which denies all outbound traffic (PostgreSQL, DNS, SMTP, federation).

### Removed `config.FITPUB_ACTIVITYPUB_ENABLED`

This key was not read by the FitPub application (ActivityPub cannot be toggled via
that environment variable). Remove it from your values if you copied it from older
chart defaults.

Quickstart verification uses `curl` against `/login` from a throwaway
`curlimages/curl` pod (the FitPub application image is a minimal JRE and does not
ship `curl` or `wget`).

## 0.3.3

### Push notifications disabled by default

`config.FITPUB_PUSH_ENABLED` now defaults to `"false"`. Enable it only after
providing `config.FITPUB_VAPID_SUBJECT` and VAPID public/private keys.

When `productionChecks.enabled: true` and `config.FITPUB_PUSH_ENABLED: "true"`,
the chart validates that `config.FITPUB_VAPID_SUBJECT` is set. For chart-managed
Secrets it also requires both `applicationSecret.data.FITPUB_VAPID_PUBLIC_KEY`
and `applicationSecret.data.FITPUB_VAPID_PRIVATE_KEY`. Existing Secrets are left
to the operator because Helm cannot inspect their data at render time.

## 0.3.2

### Artifact Hub README banner compatibility

The chart README banner now uses plain Markdown image syntax instead of an HTML
`<img>` tag, which is safer for Artifact Hub's README renderer. No runtime or
values changes.

## 0.3.1

### Artifact Hub README banner

The chart README now includes the FitPub Helm Chart banner via a raw GitHub URL,
so the package page on Artifact Hub matches the repository branding. No runtime
or values changes.

## 0.3.0

### One-command local quickstart

`scripts/local-quickstart.sh` stands up a throwaway PostGIS and installs the chart
against your current cluster, and `scripts/local-teardown.sh` removes it again. The
new `examples/postgis-dev.yaml` is the database it deploys, and
[`docs/quickstart.md`](quickstart.md) documents both the one-command and manual
paths plus a symptom/cause/fix troubleshooting table. Nothing here changes how the
chart renders; it is purely additive.

### Preflight validation of secrets and database URL

The chart now fails early, at `helm install` time, on the misconfigurations that
previously only surfaced as a pod CrashLoopBackOff:

- `applicationSecret.data.FITPUB_JWT_SECRET` / `FITPUB_EMAIL_SECRET` shorter than
  32 characters, or left at a known placeholder value, are rejected with a hint to
  run `openssl rand -base64 48`. These mirror the application's own startup checks.
  Only inline secrets are validated; `applicationSecret.existingSecret` is left to
  the operator.
- `config.FITPUB_DATABASE_URL`, when set, must start with `jdbc:postgresql://`.

**Action required** only if you were (knowingly) running with a sub-32-character
inline secret — generate a proper one. Existing valid configurations are unaffected.

### development-values.yaml uses localhost:8080

The development example now sets `FITPUB_DOMAIN`/`FITPUB_BASE_URL` to
`localhost:8080` so links generated by the app line up with the port-forward shown
in the quickstart.

## 0.2.9

### Config keys corrected to match the application

Three keys in `config` did not map to any property the application reads and have been corrected. The application behavior is unchanged on default values, but if you relied on the old keys to tune anything, move to the new ones:

| Removed / inert key | Use instead |
| --- | --- |
| `LOGGING_LEVEL_ORG_OPERATON` | `LOGGING_LEVEL_NET_JAVAHIPPIE_FITPUB` (FitPub's actual base package) |
| `FITPUB_JWT_EXPIRATION_MS` | `FITPUB_SECURITY_JWT_EXPIRATION` (binds to `fitpub.security.jwt.expiration`) |
| `FILE_UPLOAD_MAX_SIZE` | `SPRING_SERVLET_MULTIPART_MAX_FILE_SIZE` / `SPRING_SERVLET_MULTIPART_MAX_REQUEST_SIZE` |

**Action required** only if you set any of the old keys in your own values — rename them, otherwise the change is transparent.

### New config knobs: `FITPUB_FEDERATION_PROTOCOL`, `FITPUB_ALLOW_PRIVATE_IPS`

`FITPUB_FEDERATION_PROTOCOL` (default `https`) controls the protocol used in generated federation URLs, and `FITPUB_ALLOW_PRIVATE_IPS` (default `false`) controls whether federation requests to private/loopback ranges are allowed. Keep the production defaults; the development example flips both for local federation testing.

### Validation: `config.FITPUB_DOMAIN` must be a bare host

`FITPUB_DOMAIN` must be a host with an optional port (`example.fit` or `example.fit:8443`), never a URL. Setting a scheme or a trailing slash now fails rendering, because it produces broken WebFinger/ActivityPub handles such as `acct:user@https://example.fit`.

### NOTES.txt — write-test command used hardcoded path

The `kubectl exec` write-test command shown after `helm install` used the hardcoded path `/app/uploads` instead of the configured `persistence.mountPath`. If you set a custom mount path, the command shown in NOTES would silently try to write to the wrong directory. The command now always reflects the configured value.

### Validation: `dnsPolicy: None` requires `dnsConfig.nameservers`

If `dnsPolicy` is set to `None` without providing `dnsConfig.nameservers`, `helm install`/`helm upgrade` now fails with a descriptive error. Previously this configuration was accepted by the chart but rejected by the Kubernetes admission controller with a non-obvious pod startup error.

## 0.2.8

### PDB — `minAvailable: 0` and `maxUnavailable: 0` now work correctly

Go templates treat `0` as falsy. Previously, setting `podDisruptionBudget.maxUnavailable: 0` (meaning "no pod may be voluntarily evicted") triggered a false "one of minAvailable or maxUnavailable must be set" error at render time. Setting `minAvailable: 0` would silently fall through to the `else` branch and render `maxUnavailable: 1` instead — the PDB spec the user expected was never created.

Both the validation logic and the spec rendering now use `toString` comparison against `""` so that zero is treated as an explicitly set value.

### HPA — validation for empty metrics list

If both `autoscaling.targetCPUUtilizationPercentage` and `autoscaling.targetMemoryUtilizationPercentage` are absent, empty, or zero when `autoscaling.enabled: true`, `helm install`/`helm upgrade` now fails with a descriptive error. Previously this would render an HPA with `metrics: null`, which Kubernetes rejects at apply time with a non-obvious error.

### release workflow — `timeout-minutes: 30`

The release CI job now has a 30-minute timeout, preventing a hung release job from holding the runner for up to six hours.

## 0.2.7

### New value: `persistence.mountPath`

`persistence.mountPath` (default `/app/uploads`) now controls where the uploads PVC is mounted inside the container. It replaces the previously hardcoded `/app/uploads` path in the Deployment template.

**Action required** only if you set `config.FILE_UPLOAD_DIR` to a non-default path: also set `persistence.mountPath` to the same value, or the chart will now refuse to render with an error explaining the mismatch.

### Validation: `config.FILE_UPLOAD_DIR` must match `persistence.mountPath`

If `persistence.enabled: true` and `config.FILE_UPLOAD_DIR` is set to a different value than `persistence.mountPath`, `helm install` / `helm upgrade` now fails with a descriptive error. Previously, this misconfiguration caused uploads to be written to ephemeral container storage, silently losing all files on pod restart.

### Validation: `config.FITPUB_PAGES_PATH` must match `pages.mountPath`

If `pages.existingSecret` is set and `config.FITPUB_PAGES_PATH` differs from `pages.mountPath`, the chart now fails with a descriptive error. Previously, the pages Secret was mounted at one path while the application read from a different path, resulting in missing pages with no visible error at install time.

### Validation: VAPID keys required when push is enabled (productionChecks)

When `productionChecks.enabled: true` and `config.FITPUB_PUSH_ENABLED: "true"`, the chart now validates that both `applicationSecret.data.FITPUB_VAPID_PUBLIC_KEY` and `applicationSecret.data.FITPUB_VAPID_PRIVATE_KEY` are provided for chart-managed Secrets, or that `applicationSecret.existingSecret` is used. Previously, deploying with push enabled but no VAPID keys was silently accepted, resulting in broken push notifications.

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
