# Troubleshooting

Unless noted otherwise, examples assume Helm release name **`fitpub`**. If you used
a different release name, replace `app.kubernetes.io/instance=fitpub` in the label
selectors below.

## Pod Is Stuck In `CrashLoopBackOff`

Check application logs first:

```bash
kubectl logs -l app.kubernetes.io/instance=fitpub
```

Usual suspects:

- wrong database URL, username or password
- PostgreSQL without PostGIS
- missing `FITPUB_JWT_SECRET` or `FITPUB_EMAIL_SECRET`
- a failed Flyway migration
- uploads directory not writable by UID/GID `1001`

## Database Or PostGIS Errors

FitPub requires PostgreSQL with PostGIS. A plain PostgreSQL database can connect successfully but still fail during migration when the app tries to enable or use the `postgis` extension.

Verify from the database:

```sql
SELECT postgis_version();
```

If this fails, use a PostGIS-capable database image, managed service or operator.

## Health Probes

The chart defaults to **`GET /login`** (HTTP 200) for startup, readiness and liveness
probes on FitPub **1.1.1**. The login page is public in Spring Security and is only
served once the web stack has finished starting (including Flyway migrations).

| Probe | Default path | Expected code |
|---|---|---|
| `startupProbe` | `/login` | 200 |
| `readinessProbe` | `/login` | 200 |
| `livenessProbe` | `/login` | 200 |

**Limitation on 1.1.1:** `GET /login` does not query the database. Startup catches
PostGIS/Flyway failures, but if the database becomes unavailable **after** the pod
is Ready, probes can still succeed while authenticated features fail. Monitor PostGIS
externally until a FitPub release exposes unauthenticated actuator health endpoints.

Verify from inside the cluster:

```bash
kubectl run fitpub-login-check \
  --image=curlimages/curl:8.11.1 \
  --restart=Never \
  --rm \
  -i \
  --command -- curl -fsS -o /dev/null -w 'HTTP:%{http_code}\n' http://fitpub:8080/login
```

If probes fail or the pod restarts during startup, check logs and the database
connection:

```bash
kubectl logs -l app.kubernetes.io/instance=fitpub
```

Usual suspects:

- wrong database URL, username or password
- PostgreSQL without PostGIS
- a failed Flyway migration
- uploads directory not writable by UID/GID `1001`
- startup budget blown on a slow node (raise `startupProbe.failureThreshold`)

### Actuator probes (after a future FitPub release)

FitPub **1.1.1** requires authentication for `/actuator/health/**`. Unauthenticated
kubelet probes receive **HTTP 302** or **403**, and Kubernetes treats **302 as
success** - so actuator probes are unreliable on 1.1.1.

When you deploy a FitPub image that permits unauthenticated `/actuator/health/**`,
override probes for DB-aware readiness:

```yaml
startupProbe:
  httpGet:
    path: /actuator/health
    port: http
  initialDelaySeconds: 15
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 18

readinessProbe:
  httpGet:
    path: /actuator/health/readiness
    port: http
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

livenessProbe:
  httpGet:
    path: /actuator/health/liveness
    port: http
  periodSeconds: 15
  timeoutSeconds: 5
  failureThreshold: 3
```

## ServiceMonitor Returns No Metrics

The chart can create a `ServiceMonitor` that scrapes `/actuator/metrics`, but
FitPub **1.1.1** requires authentication for all actuator endpoints. Prometheus
receives HTTP **302/403** unless the app image permits unauthenticated actuator
access or you configure scrape authentication.

Do not enable `serviceMonitor.enabled` expecting useful metrics on 1.1.1 without
one of those workarounds. Do not treat an empty Prometheus target as proof that
FitPub is unhealthy - chart probes intentionally use `GET /login` instead. See
the Monitoring section in README.md.

## NetworkPolicy Blocks Traffic

If FitPub goes quiet after you enable `networkPolicy`, start with ingress. Setting
`networkPolicy.ingress.enabled=false` with no `networkPolicy.ingress.extraRules`
denies **all** inbound traffic - the chart fails at render time for that combo, so
you should never hit it by accident.

If the pod instead crashes with `UnknownHostException` on the database host, it is
egress DNS. Some enforcers drop UDP 53 to the cluster DNS even under an allow-all
egress rule - we watched kindnet do exactly that on a recent build. Allow DNS
explicitly (to kube-system on UDP/TCP 53, see the NetworkPolicy section in
[README.md](../README.md)) and confirm it works on your CNI before trusting it.

## Broken ActivityPub Or WebFinger URLs

`FITPUB_BASE_URL` must not end with a slash.

Use:

```yaml
config:
  FITPUB_BASE_URL: "https://example.com"
```

Do not use:

```yaml
config:
  FITPUB_BASE_URL: "https://example.com/"
```

A trailing slash can produce URLs with double slashes, which can break federation with some servers.

## Uploads Are Not Writable

FitPub runs as UID/GID `1001`, and the pod `fsGroup` takes care of volume ownership
on most storage classes. (The `volume-permissions` init container exists for the
oddballs that ignore `fsGroup`, but it is off by default.)

Using `persistence.existingClaim`? Check the volume is actually writable:

```bash
kubectl exec deployment/fitpub -n fitpub -- \
  sh -c 'touch /app/uploads/.write-test && rm /app/uploads/.write-test'
```

Replace `fitpub` with your Helm release name and namespace if they differ.

If this fails, fix the volume ownership or storage class permissions.

## Markdown Pages Do Not Update

When mounting pages through `pages.existingSecret`, Kubernetes updates the mounted files eventually, but the application may not reload them immediately.

Restart FitPub after changing the Secret if the UI still shows old content:

```bash
kubectl rollout restart deployment/fitpub -n fitpub
```

## Application Logs

The `prod` profile writes rotated logs to `/app/logs/`, which the chart mounts as
emptyDir. They survive container restarts but vanish when the pod is rescheduled.
For anything you need to keep, use a cluster log collector (stdout has the same
lines) or a sidecar. See **Application Logs** in [README.md](../README.md).

## Release Badge Is Red

The badge reflects the last `Release Helm Chart` run. When a release fails, check that:

- GitHub Actions can write repository contents (`contents: write`)
- the workflow token can push to `gh-pages`
- the GPG signing secrets (`GPG_KEYRING_BASE64`, `GPG_PASSPHRASE`) are set, since packaging signs the chart

## Artifact Hub Reports Deleted Chart Versions

Artifact Hub reads every version listed in the published `index.yaml`. The chart packages live on `gh-pages`, so if you delete a `.tgz` there but leave its entry in `index.yaml`, Artifact Hub will keep trying to download it and report `not found`.

Remove the affected version from `gh-pages/index.yaml` and push the branch, or restore the package. Never drop a `.tgz` without updating the index.
