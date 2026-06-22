# Design Notes

## Why I built this

I came across FitPub at Hackergarten Luzern on 4 June 2026. I had already been interested in decentralization and federated software, and the project clicked with that. I work in DevOps, so my first question was practical: how do I actually run this on Kubernetes?

There was no Helm chart for a proper deployment, and I did not expect one to show up in the upstream repo anytime soon. So I started this chart myself - mainly to get a test instance running on Infomaniak KaaS, but also to make self-hosting a bit less painful for anyone else who wants to try FitPub without writing manifests from scratch.

This is still an unofficial, personal chart. I use it, I test it, and I improve it when I hit real problems. Feedback and PRs are welcome.

## Known limitations

Things I have not fully validated yet, or that are intentionally out of scope:

- **Single replica by default.** I run and test with one pod. More replicas need shared storage for uploads and a closer look at background jobs and federation — I have not done that end-to-end.
- **No bundled database.** You bring PostGIS yourself (managed service, operator, or something you maintain). The chart only wires FitPub to it.
- **HPA is there, but not a recommendation.** The template exists; I would not scale FitPub horizontally without testing uploads and federation behavior first.
- **ServiceMonitor is optional.** Default scrape path is `/actuator/metrics`.
  FitPub 1.1.x requires authentication for actuator endpoints, so Prometheus
  scrapes fail unless the app image changes or scrape auth is configured.
  `/actuator/prometheus` is not in the 1.1.1 app image.
- **Default memory targets Java 25.** Request and limit are both **3072Mi** so
  scheduling matches `-XX:MaxRAMPercentage=75` against the cgroup limit.
- **Probes use `GET /login` by default** so FitPub 1.1.1 starts reliably under
  `helm install --wait`. After startup, `/login` does not detect database outages.
- **Not battle-tested at scale.** CI covers lint, render, API validation, and a weekly smoke install with PostGIS. That is not the same as a long-running public instance under load.
- **Changing an external Secret does not restart pods.** If you use `applicationSecret.existingSecret`, roll the Deployment yourself or use something like Reloader (see `commonAnnotations` in `values.yaml`). With `productionChecks.enabled=true`, Helm cannot verify that the external Secret contains the required keys — check them before install.

If you find something missing or wrong, open an issue - especially around production federation and multi-instance setups.

## External PostGIS

FitPub requires PostgreSQL with PostGIS. This chart intentionally does not install PostgreSQL as a subchart.

Reasons:

- production databases usually have separate backup, monitoring and upgrade policies;
- PostGIS support must be explicit, not accidentally replaced with plain PostgreSQL;
- keeping the application chart dependency-free makes upgrades and ownership clearer.

Use a managed PostgreSQL/PostGIS service or a database operator maintained by your platform team.

## Deployment With PVC

The chart uses a `Deployment` plus a dedicated uploads PVC instead of a `StatefulSet`.

Reasons:

- FitPub is a single HTTP application container, not a clustered stateful database;
- the only first-class persistent path managed by the chart is `/app/uploads`;
- a standalone PVC keeps migration to an existing claim straightforward.

The default deployment strategy is `Recreate` to avoid two pods writing to a `ReadWriteOnce` uploads volume during upgrades.

## Single Replica Default

FitPub defaults to one replica. Multiple replicas need additional validation around:

- uploaded files and shared storage semantics;
- scheduled/background work;
- federation inbox processing;
- database connection pool sizing;
- cache and temporary file behavior.

HPA support is available for advanced operators, but it is not a recommendation to scale FitPub horizontally without testing.

## CI Guarantees

The CI pipeline verifies:

- chart linting with `ct lint`;
- rendering with default values;
- rendering with `examples/production-values.yaml`;
- Kubernetes API validation in kind using `kubectl apply --dry-run=server`.

The **Kind Runtime Test** workflow (`.github/workflows/runtime-smoke-test.yaml`) runs on
every pull request and push to `main` (when chart or example files change), plus weekly
on a schedule. It verifies:

- a kind cluster starts and nodes become Ready;
- a temporary PostGIS deployment becomes available;
- FitPub installs with `helm upgrade --install --wait`;
- the pod reaches Ready without restarts during startup (startup/readiness probes);
- `/login` responds with HTTP 200 inside the cluster;
- a second install with `examples/networkpolicy-smoke-values.yaml` succeeds under restricted egress (PostGIS + DNS + HTTPS only).

This test pulls the FitPub and PostGIS container images and is slower than lint/render
checks, but it is the closest automated proof that the chart is alive end-to-end.
