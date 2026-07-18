# Upgrade Notes

## 0.5.1

`appVersion` bumped to FitPub **1.2.1**, an upstream bug-fix release (federation
activity times, analytics and logging fixes). No chart configuration changes: the
container image, actuator security, required env and probe endpoints are identical
to 1.2.0.

**Action required:** none. `helm upgrade` picks up the new image.

## 0.5.0

FitPub 1.2.0 support. `appVersion` is now **1.2.0**. Several upstream changes
require operator action - read before you `helm upgrade`.

### Actuator is now behind HTTP basic auth - `FITPUB_ACTUATOR_PASSWORD` is required

FitPub 1.2.0 protects **every** `/actuator` endpoint (health, info, prometheus)
with HTTP basic auth. In the prod profile the actuator password has no default, so
**the pod fails to start without `FITPUB_ACTUATOR_PASSWORD`**.

**Action required:** add `FITPUB_ACTUATOR_PASSWORD` to your Secret (or
`applicationSecret.data`). The username defaults to `actuator`; override with
`config.FITPUB_ACTUATOR_USERNAME`. With `productionChecks.enabled=true` the chart
now fails the render if an inline `FITPUB_ACTUATOR_PASSWORD` is missing.

```bash
kubectl create secret generic fitpub-secret \
  ... \
  --from-literal=FITPUB_ACTUATOR_PASSWORD="$(openssl rand -base64 48)"
```

### Health probes now use the authenticated actuator health groups

FitPub 1.2.0 enables the Spring Boot readiness/liveness probe groups
(`/actuator/health/readiness`, `/actuator/health/liveness`), but every `/actuator`
endpoint is behind basic auth, so a plain `httpGet` probe gets 401. The chart uses
`exec` probes that run the image's own `wget` and build the basic-auth header from
`FITPUB_ACTUATOR_USERNAME` (default `actuator`) and `FITPUB_ACTUATOR_PASSWORD` in
the pod env - the password never enters the pod spec, and it works with
`existingSecret`. There is **no separate management port**: everything, actuator
included, is served on `FITPUB_PORT` (8080).

This replaces the previous `GET /login` probe. Readiness now follows Spring's
`readinessState`, so it goes `OUT_OF_SERVICE` during the graceful-shutdown drain and
kube-proxy stops routing to a terminating pod; liveness follows `livenessState`, so
a DB outage does not restart pods.

**Action required:** none for a stock install (`FITPUB_ACTUATOR_PASSWORD` is already
required, see above). If you pinned custom `/login` probes, you can drop the override
to pick up the actuator probes, or keep `/login` - it still works. Neither health
group re-checks the DB; see docs/troubleshooting.md for DB-gated readiness.

### `FILE_UPLOAD_DIR` renamed to `FITPUB_FILE_UPLOAD_DIR`

FitPub 1.2.0 renamed the upload-directory variable. The chart now sets
`config.FITPUB_FILE_UPLOAD_DIR` and validates it against `persistence.mountPath`.

**Action required:** if you set `config.FILE_UPLOAD_DIR` in your own values, rename
it to `config.FITPUB_FILE_UPLOAD_DIR`. The old key is silently ignored by 1.2.0.

### Image and tile-cache paths moved to `/tmp`

FitPub 1.2.0 changed the defaults for generated images and the OSM tile cache to
`/app/images` and `/app/tiles`. Those sit on the **read-only** container root when
`securityContext.readOnlyRootFilesystem` is on (the chart default), so writes would
fail. The chart now sets `FITPUB_IMAGES_PATH=/tmp/fitpub/images` and
`FITPUB_TILE_CACHE_PATH=/tmp/fitpub/tiles`, backed by the existing `/tmp` emptyDir.

**Action required:** none for a stock install. Heavy tile/image usage shares the
1Gi `ephemeralVolumes.tmp.sizeLimit` - raise it, or mount dedicated volumes at those
paths via `volumes`/`volumeMounts` and override the two env vars.

### ServiceMonitor scrapes `/actuator/prometheus` with basic auth

FitPub 1.2.0 ships `micrometer-registry-prometheus`, so `/actuator/prometheus` now
returns the Prometheus exposition format. The chart default `serviceMonitor.path` is
now `/actuator/prometheus`. Because actuator is behind basic auth, scraping requires
`serviceMonitor.basicAuth` pointing at a Secret (in the ServiceMonitor namespace)
with the actuator username and password.

**Action required:** if you scrape metrics, create the auth Secret and set
`serviceMonitor.basicAuth` (see `values.yaml` for the exact shape).

### New optional config keys

- `FITPUB_CORS_ALLOWED_ORIGINS` - comma-separated browser origins; empty defaults to
  `FITPUB_BASE_URL`.
- `FITPUB_ADMIN_EMAILS` - comma-separated emails bootstrapped into the new instance
  admin role.

**Action required:** none. Both default to empty (unchanged behaviour).

### Graceful shutdown

FitPub 1.2.0 enables Spring Boot graceful shutdown with a 30-second drain window.
The chart `terminationGracePeriodSeconds` (default 60) already covers the preStop
sleep (5s) plus the drain window (30s). No action required.

### Known limitation: memory-dump admin feature

The 1.2.0 admin memory-dump feature writes to `/app/dumps`, which is read-only under
`readOnlyRootFilesystem` and has no path override. If you use it, mount a writable
volume at `/app/dumps` via `volumes`/`volumeMounts`.

## 0.4.4

Bug fix only. No appVersion change (still FitPub 1.1.1).

### Push/VAPID validation no longer gated behind productionChecks

The render-time check "FITPUB_PUSH_ENABLED=true requires FITPUB_VAPID_SUBJECT and
VAPID keys" previously ran only with productionChecks.enabled=true. It now runs
unconditionally, matching the JWT/email secret length checks.

**Action required:** none. Installs that enable push without VAPID keys now fail
at render time instead of at application startup.

## 0.4.3

Maintenance release: chart cleanup, CI hardening, and two minor behaviour changes.
No `appVersion` change (still FitPub 1.1.1).

### Trimmed default `config`

`values.yaml` now lists only the keys the chart sets a non-default value for. The
empty-string "documentation" keys (Hikari pool, ActivityPub inbox tuning, optional
mail, `FITPUB_OSM_TILES_ENABLED`, `FITPUB_WEATHER_ENABLED`) were already omitted from
the rendered ConfigMap, so removing them changes nothing at runtime. The chart also
no longer pins a handful of non-default logging keys (`LOGGING_LEVEL_ORG_FLYWAYDB`
and the `FITPUB_LOG_*` rotation knobs); those now fall back to the app's prod-profile
defaults.

**Action required:** none for a stock install. If you relied on the chart's default
log-rotation values or Flyway log level, set them explicitly under `config` or via
`extraEnv`. Keys you already set in your own values are unaffected.

### Removed inline-secret placeholder validation

The chart no longer rejects placeholder strings (e.g. `changeme`) in inline secrets.
The application already refuses to start with them, and the minimum-length checks
(JWT/email ≥ 32, database password ≥ 12) remain. Use an external `existingSecret`
for production.

**Action required:** none.

### Internal cleanup (no runtime effect)

- The metadata `annotations:` block is now a shared template helper; rendered output
  is byte-for-byte identical.
- CI validates the full production manifest set - including Ingress and
  PodDisruptionBudget - against the API server.
- Example value files no longer pin `image.tag`; it defaults to the chart appVersion.
- Validation guards already covered by `values.schema.json` were removed as dead code.

## 0.4.2

Icon fix only. Nothing to do on upgrade.

Corrects the chart icon shown on Artifact Hub. The bump is needed because Artifact Hub
only re-fetches the icon when it tracks a new chart version.

## 0.4.1

Distribution and supply-chain only. No chart behavior changes, nothing to do on upgrade.

### OCI registry

The chart now ships to GHCR as an OCI artifact next to the existing HTTP repo:

```bash
helm install fitpub oci://ghcr.io/oliinykdm/charts/fitpub --version 0.4.1
```

### cosign signatures

OCI artifacts are signed with cosign keyless (sigstore). Verify with:

```bash
cosign verify ghcr.io/oliinykdm/charts/fitpub:0.4.1 \
  --certificate-identity-regexp '^https://github.com/oliinykdm/fitpub-helm/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

The GPG provenance still travels with both the OCI and HTTP packages, so `helm pull --verify` keeps working too.

### GitHub Releases

Each version now gets a GitHub Release with the changelog and the packaged `.tgz` and `.prov`.

## 0.4.0

The "make it production-grade by default" release. Most of these flip a default that
used to be opt-in, so read before you `helm upgrade`.

### `readOnlyRootFilesystem` is now on by default

The container root filesystem is mounted read-only. FitPub still writes uploads,
logs and temp files, so the chart now also mounts emptyDir at `/tmp` (OSM tile cache
and image generation) and `/app/logs` (logback). Tune them under `ephemeralVolumes`.

**Action required:** none for a stock install. If you added custom code paths that
write outside `/app/uploads`, `/tmp` or `/app/logs`, give them a writable mount or
set `securityContext.readOnlyRootFilesystem: false`.

### `volume-permissions` init container is now off by default

`fsGroup` with `fsGroupChangePolicy: OnRootMismatch` already fixes upload ownership
without a root init container, which also keeps the pod inside the `restricted` Pod
Security Standard. Re-enable it (`initContainers.volumePermissions.enabled: true`)
only for storage classes that ignore `fsGroup`.

### PodDisruptionBudget, CPU limit and preStop hook on by default

- `podDisruptionBudget.enabled: true` with `maxUnavailable: 1`. That value keeps node
  drains working at any replica count - `minAvailable: 1` on a single replica would
  block all voluntary evictions, including node drains.
- `resources.limits.cpu: 1500m` caps GC and Flyway bursts.
- A 5-second `preStop` sleep covers the SIGTERM/endpoint-removal race during rollouts.

**Action required:** none, but if you set your own PDB values they still win.

### ServiceMonitor path back to `/actuator/metrics`

`/actuator/prometheus` does not exist in the 1.1.1 image (no Prometheus registry),
so the default path is `/actuator/metrics` again, with optional `serviceMonitor.basicAuth`.
Scraping still needs an app-side change before it returns anything useful.

### NetworkPolicy: ingress `from` selector

`networkPolicy.ingress.from` lets you restrict who can reach the app port instead of
allowing every source. Note that some enforcers (kindnet, recent builds) drop DNS
under an allow-all egress rule, which shows up as `UnknownHostException`. Allow DNS
to kube-system explicitly and verify on your CNI. See the NetworkPolicy section in README.

## 0.3.8

### `config`/`applicationSecret.data`: boolean `false` and `0` are no longer dropped

These maps were rendered with a truthiness test, so `false` or `0` silently
disappeared and the app fell back to its own default. They are now rendered as long
as they are non-empty. Empty strings and `null` are still skipped.

**Action required:** none if you used strings. If you "unset" a key with `false`/`0`,
use an empty string or drop the key instead.

### Doc fixes

- README restricted-egress example: ClusterIP DNS now allows TCP 53, and SMTP `587`
  is a separate rule instead of being attached to the DNS rule.
- `examples/production-values.yaml`/README now add `FITPUB_MAIL_USERNAME` and
  `FITPUB_MAIL_PASSWORD` to the Secret, since the examples set `FITPUB_MAIL_SMTP_AUTH=true`.
- Documented that `volume-permissions` runs as root and must be disabled under the
  `restricted` Pod Security Standard (rely on `fsGroup`).

## 0.3.7

### Mail defaults no longer forced without a host

The chart no longer renders `FITPUB_MAIL_PORT`, SMTP auth, or STARTTLS settings into
the ConfigMap unless you set them explicitly. Previously, empty `FITPUB_MAIL_HOST`
combined with port `587` and forced auth could make FitPub talk to `localhost:587`
instead of the application default `localhost:25`.

**Action required:** if you relied on chart defaults for SMTP, add mail settings to
your values when `FITPUB_MAIL_HOST` is set - see
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

**Action required** only if you tuned requests down manually - raise them again or
lower `MaxRAMPercentage` via `JAVA_TOOL_OPTIONS`.

### ConfigMap omits empty `config` values

Non-empty `config` keys are rendered into the ConfigMap, empty strings are skipped.
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

## Older versions (0.3.5 and earlier)

Per-version upgrade notes for 0.3.5 and earlier are attached to each
[GitHub Release](https://github.com/oliinykdm/fitpub-helm/releases). The headline
changes across that range: the move to `GET /login` probes (0.3.4), Java 25 memory
sizing (0.3.5/0.3.6), the ConfigMap/Secret split (0.2.0), and the preflight
validations that fail bad values at install time (0.3.0 onward).
