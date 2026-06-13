# Upgrade Notes

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
