<p align="center">
  <img src="docs/banner.png" alt="FitPub Helm Chart" width="820">
</p>

<h1 align="center">FitPub Helm Chart</h1>

<p align="center">
  Helm chart for <a href="https://codeberg.org/fitpub/fitpub">FitPub</a>, a federated fitness tracking platform.<br>
  Live instance: <a href="https://fitpub.social"><strong>fitpub.social</strong></a>
</p>

<p align="center">
  <a href="https://fitpub.social"><img src="https://img.shields.io/badge/live-fitpub.social-FF1E8E?logo=activitypub&logoColor=white" alt="Live instance"></a>
  <a href="https://artifacthub.io/packages/search?repo=fitpub"><img src="https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/fitpub" alt="Artifact Hub"></a>
  <img src="https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Foliinykdm%2Ffitpub-helm%2Fmain%2Fcharts%2Ffitpub%2FChart.yaml&query=%24.version&label=chart&color=7C3AED" alt="Chart Version">
  <img src="https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Foliinykdm%2Ffitpub-helm%2Fmain%2Fcharts%2Ffitpub%2FChart.yaml&query=%24.appVersion&label=app&color=blue" alt="App Version">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="License"></a>
</p>

<p align="center">
  <a href="https://github.com/oliinykdm/fitpub-helm/actions/workflows/helm-lint-and-test.yaml"><img src="https://github.com/oliinykdm/fitpub-helm/actions/workflows/helm-lint-and-test.yaml/badge.svg" alt="Lint and Test"></a>
  <a href="https://github.com/oliinykdm/fitpub-helm/actions/workflows/runtime-smoke-test.yaml"><img src="https://github.com/oliinykdm/fitpub-helm/actions/workflows/runtime-smoke-test.yaml/badge.svg" alt="Kind Runtime Test"></a>
  <a href="https://github.com/oliinykdm/fitpub-helm/actions/workflows/release.yaml"><img src="https://github.com/oliinykdm/fitpub-helm/actions/workflows/release.yaml/badge.svg" alt="Release"></a>
  <img src="https://img.shields.io/badge/kubernetes-%3E%3D1.26-blue" alt="Kubernetes">
  <img src="https://img.shields.io/badge/helm-%3E%3D3.8-blue" alt="Helm">
</p>

> **Status:** (Unofficial!) production-oriented chart in active development. Review values carefully before exposing a public instance. Work in progress. 

## Validation Status

- Helm lint: enabled in CI with `ct lint`
- Render tests: default values, `examples/production-values.yaml`, and `examples/networkpolicy-smoke-values.yaml`
- Kubernetes API validation: kind cluster with `kubectl apply --dry-run=server`
- **Kind runtime test** (badge *Kind Runtime Test*): on every PR/push to `main` and weekly — kind cluster, PostGIS, `helm install --wait`, pod Ready, startup/readiness probes green, in-cluster `GET /login` HTTP 200 (FitPub **1.1.1**); a second job verifies `networkpolicy-smoke-values.yaml` with restricted egress
- Release packaging: signed packages and `index.yaml` are published to GitHub Pages
- Production status: ready for controlled testing, not yet broadly battle-tested

## Features

- Deployment running as the non-root FitPub user (`1001`)
- PersistentVolumeClaim for user uploads at `/app/uploads`
- Optional Secret mount for Markdown legal/about pages at `/app/pages`
- ConfigMap/Secret split for non-secret and secret environment variables
- Probes on `GET /login` (HTTP 200) for reliable startup with FitPub **1.1.1** (actuator health requires authentication in 1.1.x); see [docs/troubleshooting.md](docs/troubleshooting.md)
- Optional Ingress, HPA, PDB, NetworkPolicy and ServiceMonitor templates
- Extension points for extra env, envFrom, volumes, volume mounts, init containers and sidecars
- Support for an external PostgreSQL database with PostGIS

## Quick start (local)

Want to try it on a local cluster (kind/minikube/Docker Desktop) without wiring up
a database first? From the repository root:

```bash
scripts/local-quickstart.sh
```

This deploys a throwaway PostGIS, installs the chart, waits until it is healthy and
prints how to reach it. See [docs/quickstart.md](docs/quickstart.md) for the manual
steps and a troubleshooting table.

## Prerequisites

- Kubernetes 1.26+
- Helm 3.8+
- External PostgreSQL with PostGIS enabled. A plain PostgreSQL database is not enough.

## Installation

Charts are published through GitHub Pages by the release workflow:

```bash
helm repo add fitpub https://oliinykdm.github.io/fitpub-helm
helm repo update
```

Install with production values. Copy [examples/production-values.yaml](examples/production-values.yaml),
adapt it for your environment, then install:

```bash
helm install fitpub fitpub/fitpub -f production-values.yaml
```

Or install directly from the repository while developing the chart:

```bash
git clone https://github.com/oliinykdm/fitpub-helm.git
cd fitpub-helm
helm install fitpub ./charts/fitpub -f examples/production-values.yaml
```

The repository install still expects an external PostGIS database and a pre-created
Secret when using `examples/production-values.yaml`. For a working local instance
without manual wiring, use `scripts/local-quickstart.sh` instead.

## Configuration

Non-secret settings go into `config` and are rendered into a ConfigMap. Secrets go into `applicationSecret.data` or, preferably for production, into an existing Kubernetes Secret referenced by `applicationSecret.existingSecret`.

Minimum production values (use an external Secret — do not commit real credentials to Git):

```yaml
productionChecks:
  enabled: true

config:
  FITPUB_DATABASE_URL: "jdbc:postgresql://postgres:5432/fitpub"
  FITPUB_DOMAIN: "your-domain.com"
  # Must not end with a slash.
  FITPUB_BASE_URL: "https://your-domain.com"
  FITPUB_PUSH_ENABLED: "false"
  # When enabling mail, set FITPUB_MAIL_HOST together with port/auth/starttls — see production-values.yaml.
  FITPUB_MAIL_HOST: "smtp.example.com"
  FITPUB_MAIL_PORT: "587"
  FITPUB_MAIL_SMTP_AUTH: "true"
  FITPUB_MAIL_STARTTLS_ENABLE: "true"
  FITPUB_MAIL_STARTTLS_REQUIRED: "true"

applicationSecret:
  existingSecret: fitpub-secret
```

Create the Secret before install (inline `applicationSecret.data` is for controlled testing only — see [examples/chart-managed-secret-values.yaml](examples/chart-managed-secret-values.yaml)):

```bash
kubectl create secret generic fitpub-secret -n fitpub \
  --from-literal=FITPUB_DATABASE_USERNAME=fitpub \
  --from-literal=FITPUB_DATABASE_PASSWORD="$(openssl rand -base64 32)" \
  --from-literal=FITPUB_JWT_SECRET="$(openssl rand -base64 64)" \
  --from-literal=FITPUB_EMAIL_SECRET="$(openssl rand -base64 64)"
```

```yaml
applicationSecret:
  existingSecret: fitpub-secret
```

Enable `productionChecks.enabled=true` in production values. It fails rendering early when required public settings, chart-managed secrets, or incomplete push notification settings are missing.

Optional tuning keys (Hikari pool, ActivityPub inbox processing, `FITPUB_MAIL_PROTOCOL`, `FITPUB_OSM_TILES_ENABLED`, `FITPUB_WEATHER_ENABLED`, and others) are listed in [values.yaml](charts/fitpub/values.yaml). Leave them empty to use application defaults.

See [values.yaml](charts/fitpub/values.yaml) and [examples/production-values.yaml](examples/production-values.yaml) for available options.

Additional examples:

- [examples/production-values.yaml](examples/production-values.yaml): production-style values with an externally managed Secret
- [examples/chart-managed-secret-values.yaml](examples/chart-managed-secret-values.yaml): controlled testing values where Helm creates the Secret
- [examples/development-values.yaml](examples/development-values.yaml): development-style values for throwaway clusters
- [examples/runtime-smoke-values.yaml](examples/runtime-smoke-values.yaml): CI-only values used by the runtime smoke test
- [examples/networkpolicy-smoke-values.yaml](examples/networkpolicy-smoke-values.yaml): CI-only values for restricted NetworkPolicy egress

## Extending The Pod

The chart exposes common extension points without editing templates:

```yaml
extraEnv:
  - name: JAVA_TOOL_OPTIONS
    value: "-XX:MaxRAMPercentage=70"

extraEnvFrom: []
extraInitContainers: []
sidecars: []
volumes: []
volumeMounts: []
nodeSelector: {}
tolerations: []
affinity: {}
topologySpreadConstraints: []
```

Use these for platform integrations such as sidecar agents, projected Secrets, custom CA bundles or cluster scheduling rules.

## Ingress

Enable Ingress when exposing FitPub publicly:

```yaml
ingress:
  enabled: true
  className: traefik
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: fitpub.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: fitpub-tls
      hosts:
        - fitpub.example.com
```

Set `className` to the ingress controller used by your cluster. The example uses Traefik as a common self-hosted default.

FitPub's production profile enables `server.forward-headers-strategy: framework` and reads `X-Forwarded-For` and `X-Forwarded-Proto` from your ingress or reverse proxy. Configure the controller to pass those headers on HTTPS termination so generated URLs, redirects and ActivityPub endpoints use the correct public scheme.

## Markdown Pages

FitPub can read Markdown pages from `/app/pages`. To provide Kubernetes-native legal pages, create a Secret from files and mount it:

```bash
kubectl create secret generic fitpub-pages \
  --from-file=terms.md \
  --from-file=imprint.md \
  --from-file=about.md
```

```yaml
pages:
  existingSecret: fitpub-pages
```

Secret updates do not automatically restart the pod. Restart the Deployment if the application does not pick up changed files.

## Persistence

By default, the chart creates a `PersistentVolumeClaim` for user uploads at `/app/uploads`.

You can customize storage size and class:

```yaml
persistence:
  enabled: true
  storageClass: ""
  size: 10Gi
```

You can also reuse an existing claim:

```yaml
persistence:
  enabled: true
  existingClaim: fitpub-uploads
```

Back up the uploads PVC and the external PostGIS database regularly.

## Application Logs

In the `prod` Spring profile, FitPub writes rotated file logs under `/app/logs/` inside the container. This chart does **not** mount a volume there by default — logs are lost when the pod is replaced. For production, either:

- rely on your cluster log collector (stdout is mostly WARN+; file logs hold more detail), or
- mount `/app/logs` via `volumes` / `volumeMounts`, or
- ship file logs with a sidecar agent.

Example emptyDir mount (logs survive container restarts within the same pod, but not pod rescheduling):

```yaml
volumes:
  - name: logs
    emptyDir: {}
volumeMounts:
  - name: logs
    mountPath: /app/logs
```

## Replicas And Scaling

The default is `replicaCount: 1` with a `Recreate` deployment strategy. This is intentional: FitPub has local uploads and application-level background work, so multi-replica operation should be validated before enabling HPA.

If you enable `autoscaling`, make sure your storage, background jobs, federation processing and database connection pool are ready for multiple pods.

## Memory And JVM

The FitPub container image runs Java 25 with `-XX:MaxRAMPercentage=75` against the
cgroup memory **limit**. Default chart resources set request and limit to the same
value so the scheduler reserves enough RAM for heap plus native overhead:

```yaml
resources:
  requests:
    cpu: 250m
    memory: 3072Mi
  limits:
    memory: 3072Mi
```

If you see OOMKilled pods or slow Flyway startup on small nodes, raise
`resources.limits.memory` or lower the heap fraction:

```yaml
extraEnv:
  - name: JAVA_TOOL_OPTIONS
    value: "-XX:MaxRAMPercentage=60"
```

## NetworkPolicy

`networkPolicy.enabled` is disabled by default. FitPub needs egress to PostgreSQL, SMTP and federated/external HTTP services. If your cluster enforces egress policies, start with explicit rules for those dependencies.

Keep `networkPolicy.ingress.enabled=true` (the default) unless you add
`networkPolicy.ingress.extraRules`. Disabling ingress without extra rules denies
all inbound traffic to FitPub.

Example shape for restricted egress:

```yaml
networkPolicy:
  enabled: true
  egress:
    allowAll: false
    extraRules:
      - to:
          - namespaceSelector:
              matchLabels:
                kubernetes.io/metadata.name: database
        ports:
          - protocol: TCP
            port: 5432
      - to:
          - namespaceSelector:
              matchLabels:
                kubernetes.io/metadata.name: kube-system
            podSelector:
              matchLabels:
                k8s-app: kube-dns
        ports:
          - protocol: UDP
            port: 53
          - protocol: TCP
            port: 53
      - to:
          - ipBlock:
              cidr: 10.96.0.0/12
        ports:
          - protocol: UDP
            port: 53
          - protocol: TCP
            port: 587
      - ports:
          - protocol: TCP
            port: 443
```

Adjust this to your actual PostgreSQL, DNS, SMTP, HTTPS federation and peer egress model.

## Graceful Shutdown

Kubernetes sends `SIGTERM` and removes the pod from endpoints at the same time, so add a `preStop` sleep if you see connection errors during rollouts:

```yaml
lifecycleHooks:
  preStop:
    exec:
      command: ["sh", "-c", "sleep 5"]
```

Scheduling knobs (`priorityClassName`, `nodeSelector`, `tolerations`, `affinity`, `topologySpreadConstraints`) are passed through as-is — see `values.yaml`.

## Debugging

Enable `diagnosticMode` to run the container as `sleep infinity` so you can exec in without startup or probe failures blocking access:

```bash
helm upgrade fitpub fitpub/fitpub \
  --reuse-values \
  --set diagnosticMode.enabled=true

kubectl exec -it deployment/fitpub -n fitpub -- sh
```

Disable it again when done:

```bash
helm upgrade fitpub fitpub/fitpub \
  --reuse-values \
  --set diagnosticMode.enabled=false
```

## Global Labels And Annotations

Add labels and annotations to every resource created by this chart:

```yaml
commonLabels:
  environment: production
  team: platform

commonAnnotations:
  reloader.stakater.com/auto: "true"
```

## Monitoring

If your cluster runs Prometheus Operator, enable `ServiceMonitor`:

```yaml
serviceMonitor:
  enabled: true
  labels:
    release: kube-prometheus-stack
```

The default scrape path is `/actuator/metrics` (exposed in the prod Spring profile).
The FitPub **1.1.1** image does not ship `/actuator/prometheus`.

**Authentication:** Spring Security requires authentication for all actuator
endpoints on FitPub 1.1.x, including `/actuator/metrics`. Unauthenticated
Prometheus scrapes receive HTTP **302/403** and look empty. Enable ServiceMonitor
only after the app image permits unauthenticated actuator access, or configure
scrape authentication / a metrics sidecar. Probes intentionally use `GET /login`
instead — see [docs/troubleshooting.md](docs/troubleshooting.md).

## Security Notes

The chart drops Linux capabilities, disables privilege escalation and runs FitPub as UID/GID `1001`. `readOnlyRootFilesystem` is disabled by default because FitPub writes uploads, logs, temp files and caches; enabling it requires additional writable mounts for every write path.

## Upgrade

Use the same adapted values file you installed with (commonly copied from
[examples/production-values.yaml](examples/production-values.yaml)):

```bash
helm upgrade fitpub fitpub/fitpub -f production-values.yaml
```

When changing ConfigMap or chart-managed Secret values, the Deployment rolls automatically because checksum annotations are included on the pod template.

Read [docs/upgrade-notes.md](docs/upgrade-notes.md) before upgrading across chart minor versions.

## Design Notes

This chart intentionally uses an external PostGIS database, a `Deployment` with a dedicated uploads PVC and a single-replica default. See [docs/design.md](docs/design.md) for the reasoning and current CI guarantees.

## GitOps

Flux and Argo CD examples are available in [docs/gitops.md](docs/gitops.md). Production GitOps setups should manage secrets through SOPS, External Secrets Operator, Sealed Secrets or a similar workflow.

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for common Kubernetes deployment problems: PostGIS issues, missing secrets, failing health probes, PVC permissions and federation URL mistakes.

## Important Production Checklist

- Use external PostgreSQL with PostGIS.
- Enable `productionChecks.enabled=true`.
- Set `SPRING_PROFILES_ACTIVE=prod`.
- Set strong values for `FITPUB_DATABASE_PASSWORD`, `FITPUB_JWT_SECRET` and `FITPUB_EMAIL_SECRET`.
- When using `applicationSecret.existingSecret`, verify the Secret contains all required keys before install.
- Size memory for Java 25 (defaults: 3072Mi request / 3072Mi limit).
- Keep `FITPUB_PUSH_ENABLED=false` unless VAPID public/private keys and `FITPUB_VAPID_SUBJECT` are configured.
- Keep `FITPUB_BASE_URL` public, canonical and without a trailing slash.
- Put FitPub behind HTTPS.
- Back up PostgreSQL and `/app/uploads`.
- Plan for `/app/logs` (file logs in prod are not persisted unless you mount a volume or collect them).
- Validate probes against your deployed security configuration (`GET /login` on 1.1.1 does not verify database connectivity after startup).
- Do not enable `serviceMonitor` until actuator scraping is authenticated or public in your app version.
- Keep `replicaCount: 1` until multi-pod behavior has been tested.

The chart originated from the Kubernetes manifests discussion in [FitPub issue #301](https://codeberg.org/fitpub/fitpub/issues/301).

## Contributing

This chart is currently maintained in a personal repository. Once it reaches a stable state, it can be proposed to the upstream FitPub project on Codeberg.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development workflow and chart design principles.
