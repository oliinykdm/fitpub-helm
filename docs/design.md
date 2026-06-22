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
- **ServiceMonitor is optional.** Default scrape path is `/actuator/metrics`. `/actuator/prometheus` is not in the 1.1.1 app image.
- **Probes use `GET /login` by default** so FitPub 1.1.1 starts reliably under `helm install --wait`.
- **Not battle-tested at scale.** CI covers lint, render, API validation, and a weekly smoke install with PostGIS. That is not the same as a long-running public instance under load.
- **Changing an external Secret does not restart pods.** If you use `applicationSecret.existingSecret`, roll the Deployment yourself or use something like Reloader (see `commonAnnotations` in `values.yaml`).

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

The separate runtime smoke-test workflow verifies:

- a kind cluster can run the chart;
- a temporary PostGIS deployment is reachable;
- FitPub can be installed with `helm install --wait`;
- `/login` responds with HTTP 200 inside the cluster after startup.

The runtime smoke test is manual and weekly instead of mandatory on every PR because it pulls application and PostGIS images and can be slower or more sensitive to registry/network issues.
