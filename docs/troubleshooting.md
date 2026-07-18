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

FitPub 1.2.0 enables the Spring Boot probe groups at `/actuator/health/readiness`
and `/actuator/health/liveness`, but every `/actuator` endpoint is behind HTTP basic
auth (there is no separate management port - actuator lives on `FITPUB_PORT`, default
8080). An unauthenticated `httpGet` probe therefore gets a 401.

The chart uses `exec` probes that mirror the image's own `HEALTHCHECK`: the BusyBox
`wget` in the `eclipse-temurin:25-jre-alpine` base builds the basic-auth header from
`FITPUB_ACTUATOR_USERNAME` (default `actuator`) and `FITPUB_ACTUATOR_PASSWORD`, both
read from the pod env. The password never lands in the pod spec, and it works with
`applicationSecret.existingSecret`.

| Probe | Default endpoint | Reflects |
|---|---|---|
| `startupProbe` | `/actuator/health/readiness` | app finished starting (Flyway + context) |
| `readinessProbe` | `/actuator/health/readiness` | Spring `readinessState` |
| `livenessProbe` | `/actuator/health/liveness` | Spring `livenessState` |

Readiness follows `readinessState`, which flips to `OUT_OF_SERVICE` (HTTP 503) when
the graceful-shutdown drain starts, so kube-proxy stops routing to a terminating pod
- the `/login` page could not do that. Liveness follows `livenessState` only, so a
database outage does not restart pods.

One caveat: with the default health groups neither readiness nor liveness runs the
DB indicator; only the aggregate `/actuator/health` does. If PostgreSQL disappears
after the pod is Ready, the probes stay green while authenticated features fail.
Monitor PostGIS separately, or point readiness at the aggregate endpoint (below).

Verify from inside the cluster (replace `<PASSWORD>` with `FITPUB_ACTUATOR_PASSWORD`):

```bash
kubectl run fitpub-health-check \
  --image=curlimages/curl:8.11.1 \
  --restart=Never \
  --rm \
  -i \
  --command -- curl -fsS -u actuator:<PASSWORD> -o /dev/null -w 'HTTP:%{http_code}\n' \
      http://fitpub:8080/actuator/health/readiness
```

If probes fail or the pod restarts during startup, check logs and the database
connection:

```bash
kubectl logs -l app.kubernetes.io/instance=fitpub
```

Usual suspects:

- wrong `FITPUB_ACTUATOR_PASSWORD` (probe gets 401 - the pod never turns Ready)
- wrong database URL, username or password
- PostgreSQL without PostGIS
- a failed Flyway migration
- uploads directory not writable by UID/GID `1001`
- startup budget blown on a slow node (raise `startupProbe.failureThreshold`)

### DB-gated readiness (optional)

To take a pod out of the Service endpoints when its DB connection drops, point
readiness at the aggregate `/actuator/health` (which includes the `db` indicator)
instead of the readiness group:

```yaml
readinessProbe:
  exec:
    command:
      - sh
      - -c
      - >-
        wget --spider -q
        --header="Authorization: Basic $(printf '%s:%s' "${FITPUB_ACTUATOR_USERNAME:-actuator}" "$FITPUB_ACTUATOR_PASSWORD" | base64 | tr -d '\n')"
        "http://127.0.0.1:${FITPUB_PORT:-8080}/actuator/health"
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

Weigh the trade-off: on a shared-DB outage every replica goes NotReady at once, so
the Service ends up with no endpoints. Keep `livenessProbe` on
`/actuator/health/liveness` so a DB blip never restarts the pods.

### Simpler credential-free probes (fallback)

`GET /login` is public and returns HTTP 200 once the web layer is up, so it works as
a probe without actuator credentials. It does not query the DB, and it keeps
returning 200 during the shutdown drain (so traffic is not drained cleanly). Use it
only if the `exec`/`wget` approach does not fit your image:

```yaml
readinessProbe:
  httpGet: { path: /login, port: http }
livenessProbe:
  httpGet: { path: /login, port: http }
startupProbe:
  httpGet: { path: /login, port: http }
```

## ServiceMonitor Returns No Metrics

The chart creates a `ServiceMonitor` scraping `/actuator/prometheus` (the FitPub
1.2.0 Prometheus endpoint). Every actuator endpoint is behind HTTP basic auth, so
without scrape credentials Prometheus receives **HTTP 401** and the target stays
empty.

Provide `serviceMonitor.basicAuth` pointing at a Secret (in the ServiceMonitor
namespace) that holds the actuator username (default `actuator`) and
`FITPUB_ACTUATOR_PASSWORD` - see the Monitoring section in README.md. An empty
target is a scrape-auth problem, not proof that FitPub is unhealthy - the pod's own
readiness probe authenticates separately.

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
