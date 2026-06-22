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
  <a href="https://github.com/oliinykdm/fitpub-helm/actions/workflows/runtime-smoke-test.yaml"><img src="https://github.com/oliinykdm/fitpub-helm/actions/workflows/runtime-smoke-test.yaml/badge.svg" alt="Runtime Smoke Test"></a>
  <a href="https://github.com/oliinykdm/fitpub-helm/actions/workflows/release.yaml"><img src="https://github.com/oliinykdm/fitpub-helm/actions/workflows/release.yaml/badge.svg" alt="Release"></a>
  <img src="https://img.shields.io/badge/kubernetes-%3E%3D1.26-blue" alt="Kubernetes">
  <img src="https://img.shields.io/badge/helm-%3E%3D3.8-blue" alt="Helm">
</p>

> **Status:** (Unofficial!) production-oriented chart in active development. Review values carefully before exposing a public instance. Work in progress. 

## Validation Status

- Helm lint: enabled in CI with `ct lint`
- Render tests: default values and `examples/production-values.yaml`
- Kubernetes API validation: kind cluster with `kubectl apply --dry-run=server`
- Release packaging: signed packages and `index.yaml` are published to GitHub Pages
- Runtime install test: manual and weekly workflow with kind, PostGIS, `helm install --wait` and `/actuator/health`
- Production status: ready for controlled testing, not yet broadly battle-tested

## Features

- Deployment running as the non-root FitPub user (`1001`)
- PersistentVolumeClaim for user uploads at `/app/uploads`
- Optional Secret mount for Markdown legal/about pages at `/app/pages`
- ConfigMap/Secret split for non-secret and secret environment variables
- Readiness, startup and liveness probes on `/actuator/health`
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

Install with your production values:

```bash
helm install fitpub fitpub/fitpub -f production-values.yaml
```

Or install directly from the repository while developing the chart:

```bash
git clone https://github.com/oliinykdm/fitpub-helm.git
cd fitpub-helm
helm install fitpub ./charts/fitpub
```

## Configuration

Non-secret settings go into `config` and are rendered into a ConfigMap. Secrets go into `applicationSecret.data` or, preferably for production, into an existing Kubernetes Secret referenced by `applicationSecret.existingSecret`.

Minimum production values:

```yaml
productionChecks:
  enabled: true

config:
  FITPUB_DATABASE_URL: "jdbc:postgresql://postgres:5432/fitpub"
  FITPUB_DOMAIN: "your-domain.com"
  # Must not end with a slash.
  FITPUB_BASE_URL: "https://your-domain.com"

applicationSecret:
  data:
    FITPUB_DATABASE_USERNAME: "fitpub"
    FITPUB_DATABASE_PASSWORD: "your-password"
    FITPUB_JWT_SECRET: "your-long-random-secret"
    FITPUB_EMAIL_SECRET: "your-long-random-secret"
```

For production, create the Secret outside Helm and reference it:

```bash
kubectl create secret generic fitpub-secret \
  --from-literal=FITPUB_DATABASE_USERNAME=fitpub \
  --from-literal=FITPUB_DATABASE_PASSWORD="$(openssl rand -base64 32)" \
  --from-literal=FITPUB_JWT_SECRET="$(openssl rand -base64 64)" \
  --from-literal=FITPUB_EMAIL_SECRET="$(openssl rand -base64 64)"
```

```yaml
applicationSecret:
  existingSecret: fitpub-secret
```

Enable `productionChecks.enabled=true` in production values. It fails rendering early when required public settings or chart-managed secrets are missing.

See [values.yaml](charts/fitpub/values.yaml) and [examples/production-values.yaml](examples/production-values.yaml) for available options.

Additional examples:

- [examples/production-values.yaml](examples/production-values.yaml): production-style values with an externally managed Secret
- [examples/chart-managed-secret-values.yaml](examples/chart-managed-secret-values.yaml): controlled testing values where Helm creates the Secret
- [examples/development-values.yaml](examples/development-values.yaml): development-style values for throwaway clusters
- [examples/runtime-smoke-values.yaml](examples/runtime-smoke-values.yaml): CI-only values used by the runtime smoke test

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

Set `className` to the ingress controller used by your cluster. The example uses Traefik as a common self-hosted default. FitPub's production profile uses forwarded headers, so make sure your ingress controller or gateway passes `X-Forwarded-Proto` and `X-Forwarded-Port` correctly.

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

Back up the uploads PVC and the external PostGIS database regularly. Application logs are expected to be collected by your cluster logging stack; they are not persisted by this chart by default.

## Replicas And Scaling

The default is `replicaCount: 1` with a `Recreate` deployment strategy. This is intentional: FitPub has local uploads and application-level background work, so multi-replica operation should be validated before enabling HPA.

If you enable `autoscaling`, make sure your storage, background jobs, federation processing and database connection pool are ready for multiple pods.

## NetworkPolicy

`networkPolicy.enabled` is disabled by default. FitPub needs egress to PostgreSQL, SMTP and federated/external HTTP services. If your cluster enforces egress policies, start with explicit rules for those dependencies.

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
      - ports:
          - protocol: UDP
            port: 53
          - protocol: TCP
            port: 587
```

Adjust this to your actual PostgreSQL, DNS, SMTP and federation egress model.

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

kubectl exec -it deployment/fitpub -- sh
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

The default scrape path is `/actuator/prometheus`. Make sure the FitPub application exposes that endpoint before relying on metrics scraping.

## Security Notes

The chart drops Linux capabilities, disables privilege escalation and runs FitPub as UID/GID `1001`. `readOnlyRootFilesystem` is disabled by default because FitPub writes uploads, logs, temp files and caches; enabling it requires additional writable mounts for every write path.

## Upgrade

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
- Keep `FITPUB_BASE_URL` public, canonical and without a trailing slash.
- Put FitPub behind HTTPS.
- Back up PostgreSQL and `/app/uploads`.
- Validate probes against your deployed security configuration.
- Keep `replicaCount: 1` until multi-pod behavior has been tested.

The chart originated from the Kubernetes manifests discussion in [FitPub issue #301](https://codeberg.org/fitpub/fitpub/issues/301).

## Contributing

This chart is currently maintained in a personal repository. Once it reaches a stable state, it can be proposed to the upstream FitPub project on Codeberg.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development workflow and chart design principles.
