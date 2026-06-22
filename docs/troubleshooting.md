# Troubleshooting

## Pod Is Stuck In `CrashLoopBackOff`

Check application logs first:

```bash
kubectl logs deployment/fitpub
```

Common causes:

- database URL, username or password is wrong;
- PostgreSQL does not have PostGIS available;
- `FITPUB_JWT_SECRET` or `FITPUB_EMAIL_SECRET` is missing;
- Flyway migration failed;
- the uploads directory is not writable by UID/GID `1001`.

## Database Or PostGIS Errors

FitPub requires PostgreSQL with PostGIS. A plain PostgreSQL database can connect successfully but still fail during migration when the app tries to enable or use the `postgis` extension.

Verify from the database:

```sql
SELECT postgis_version();
```

If this fails, use a PostGIS-capable database image, managed service or operator.

## Health Probes

The chart defaults to **`GET /login`** (HTTP 200) for startup, readiness and liveness
probes. The login page is public in FitPub's Spring Security configuration and is
only served once the web stack has finished starting (including Flyway migrations).

| Probe | Default path | Expected code |
|---|---|---|
| `startupProbe` | `/login` | 200 |
| `readinessProbe` | `/login` | 200 |
| `livenessProbe` | `/login` | 200 |

Verify from inside the cluster:

```bash
kubectl run fitpub-login-check \
  --image=curlimages/curl \
  --restart=Never \
  --rm \
  -i \
  --command -- curl -fsS -o /dev/null -w 'HTTP:%{http_code}\n' http://fitpub:8080/login
```

### Actuator probes (after a future FitPub release)

FitPub **1.1.1** requires authentication for `/actuator/health/**`. Unauthenticated
kubelet probes receive **HTTP 302** or **403**, and Kubernetes treats **302 as
success** — so actuator probes are unreliable on 1.1.1.

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

## Health Probes Fail

If probes fail or the pod restarts, check logs and the database connection:

```bash
kubectl logs deployment/fitpub
```

Common causes:

- database URL, username or password is wrong;
- PostgreSQL does not have PostGIS available;
- Flyway migration failed;
- the uploads directory is not writable by UID/GID `1001`;
- startup budget exhausted on a slow node (increase `startupProbe.failureThreshold`).

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

FitPub runs as UID/GID `1001`. For chart-managed PVCs, the `volume-permissions` init container and pod `fsGroup` handle ownership.

If you use `persistence.existingClaim`, verify the mounted volume is writable:

```bash
kubectl exec deployment/fitpub -- sh -c 'touch /app/uploads/.write-test && rm /app/uploads/.write-test'
```

If this fails, fix the volume ownership or storage class permissions.

## Markdown Pages Do Not Update

When mounting pages through `pages.existingSecret`, Kubernetes updates the mounted files eventually, but the application may not reload them immediately.

Restart FitPub after changing the Secret if the UI still shows old content:

```bash
kubectl rollout restart deployment/fitpub
```

## Release Badge Is Red

The badge reflects the last `Release Helm Chart` run. If a release fails, check that:

- GitHub Actions is allowed to write repository contents (`contents: write`);
- the workflow token can push to `gh-pages`;
- the GPG signing secrets (`GPG_KEYRING_BASE64`, `GPG_PASSPHRASE`) are set, since packaging signs the chart.

## Artifact Hub Reports Deleted Chart Versions

Artifact Hub reads every version listed in the published `index.yaml`. The chart packages live on `gh-pages`, so if you delete a `.tgz` there but leave its entry in `index.yaml`, Artifact Hub will keep trying to download it and report `not found`.

Remove the affected version from `gh-pages/index.yaml` and push the branch, or restore the package. Never drop a `.tgz` without updating the index.
