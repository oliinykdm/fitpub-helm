# Design Notes

## Why I built this

I came across FitPub at Hackergarten Luzern on 4 June 2026. I had already been interested in decentralization and federated software, and the project clicked with that. I work in DevOps, so my first question was practical: how do I actually run this on Kubernetes?

There was no Helm chart for a proper deployment, and I did not expect one to show up in the upstream repo anytime soon. So I started this chart myself - mainly to get a test instance running on Infomaniak KaaS, but also to make self-hosting a bit less painful for anyone else who wants to try FitPub without writing manifests from scratch.

This is still an unofficial, personal chart. I use it, I test it, and I improve it when I hit real problems. Feedback and PRs are welcome.

## Known limitations

Things I have not fully validated yet, or that are intentionally out of scope:

- **Single replica by default.** The background schedulers are actually safe to run concurrently (they claim work with row locks, the cleanups are idempotent), so the real blocker is the uploads volume - `ReadWriteOnce` only mounts on one pod. Give uploads `ReadWriteMany` storage and more replicas are fine. I just have not run a public multi-pod instance long enough to call it boring.
- **No bundled database.** You bring PostGIS yourself (managed service, operator, or something you maintain). The chart only wires FitPub to it.
- **HPA is there, but not a recommendation.** The template exists. I still would not scale FitPub horizontally without testing uploads and federation behavior first.
- **ServiceMonitor is optional.** Default scrape path is `/actuator/prometheus`,
  which FitPub 1.2.0 serves via `micrometer-registry-prometheus`. Every actuator
  endpoint is behind HTTP basic auth, so scraping needs `serviceMonitor.basicAuth`
  against the actuator credentials, otherwise Prometheus gets HTTP 401.
- **Default memory targets Java 25.** Request and limit are both **3072Mi** so
  scheduling matches `-XX:MaxRAMPercentage=75` against the cgroup limit.
- **Probes hit the actuator health groups, not `/login`.** They live on the app port
  (there is no separate management port) behind basic auth, so the chart uses `exec`
  probes that run the image's own `wget` and read the actuator password from the pod
  env - no credential in the pod spec, and it works with `existingSecret`. Readiness
  tracks Spring's readinessState so it drains on shutdown; liveness tracks
  livenessState so a database blip does not restart pods. Neither re-checks the DB;
  docs/troubleshooting.md covers gating readiness on it.
- **Not battle-tested at scale.** CI covers lint, render, API validation, and a weekly smoke install with PostGIS. That is not the same as a long-running public instance under load.
- **Changing an external Secret does not restart pods.** If you use `applicationSecret.existingSecret`, roll the Deployment yourself or use something like Reloader (see `commonAnnotations` in `values.yaml`). With `productionChecks.enabled=true`, Helm cannot verify that the external Secret contains the required keys - check them before install.

If you find something missing or wrong, open an issue - especially around production federation and multi-instance setups.

## External PostGIS

FitPub requires PostgreSQL with PostGIS. This chart intentionally does not install PostgreSQL as a subchart.

Why:

- production databases usually have their own backup, monitoring and upgrade policies
- PostGIS has to be explicit, not accidentally swapped for plain PostgreSQL
- a dependency-free app chart keeps upgrades and ownership clear

Use a managed PostgreSQL/PostGIS service or a database operator your platform team owns.

## Deployment With PVC

The chart uses a `Deployment` plus a dedicated uploads PVC instead of a `StatefulSet`.

Why:

- FitPub is one HTTP container, not a clustered stateful database
- the only first-class persistent path the chart owns is `/app/uploads`
- a standalone PVC makes moving to an existing claim painless

The strategy is `Recreate` so two pods never fight over a `ReadWriteOnce` uploads volume mid-upgrade.

## Single Replica Default

One replica out of the box. To go wider, the things to get right are:

- shared storage for uploads (`ReadWriteMany`)
- database connection pool sizing for N pods
- temp file and cache behavior per pod

The schedulers and federation inbox already handle concurrency via DB row locks, so
they are not the blocker - storage is. HPA is wired up for operators who want it, but
"the template exists" is not the same as "I recommend scaling blind".

## CI Guarantees

CI verifies:

- chart linting with `ct lint`
- rendering with default values
- rendering with `examples/production-values.yaml` and `examples/networkpolicy-smoke-values.yaml`
- Kubernetes API validation in kind with `kubectl apply --dry-run=server`

The **Kind Runtime Test** workflow (`.github/workflows/runtime-smoke-test.yaml`) runs on
every pull request and push to `main` (when chart or example files change), plus weekly
on a schedule. It verifies:

- a kind cluster starts and nodes become Ready
- a temporary PostGIS deployment becomes available
- FitPub installs with `helm upgrade --install --wait`
- the pod reaches Ready without restarts during startup (startup/readiness probes)
- `/login` responds with HTTP 200 inside the cluster
- a second install with `examples/networkpolicy-smoke-values.yaml` survives restricted egress (PostGIS + DNS + HTTPS only)

It pulls the FitPub and PostGIS images so it is slower than the lint/render checks,
but it is the closest thing to proof that the chart actually boots.
