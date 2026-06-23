# Upgrade Notes

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
