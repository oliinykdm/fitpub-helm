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

## Health Probes Fail

The default probes use:

```text
/actuator/health
```

Check from inside the cluster:

```bash
kubectl run fitpub-healthcheck \
  --image=curlimages/curl \
  --restart=Never \
  --rm \
  -i \
  --command -- curl -fsS http://fitpub:8080/actuator/health
```

If the endpoint is blocked by application security settings, adjust probes or the application configuration before relying on Kubernetes readiness.

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

The release badge reflects the last completed `Release Helm Chart` workflow run. If the first release failed before `gh-pages` existed, merge the workflow fix and rerun the workflow manually.

If it still fails, check:

- repository permissions allow GitHub Actions to write contents;
- branch protection allows the workflow token to push `gh-pages`;
- the chart version has not already been released, or `skip_existing` is enabled.

## Artifact Hub Reports Deleted Chart Versions

Artifact Hub reads every version listed in the published Helm `index.yaml`. If a GitHub Release or `.tgz` package is deleted manually but the version remains in `gh-pages/index.yaml`, Artifact Hub will keep trying to download it and report `not found`.

Fix options:

- rerun the `Release Helm Chart` workflow, which prunes missing package URLs from `index.yaml`;
- or manually remove deleted versions from `gh-pages/index.yaml` and push the branch.

Do not delete release assets without also updating the Helm repository index.
