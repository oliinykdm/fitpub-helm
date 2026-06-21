# Design Notes

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

The CI pipeline does not yet verify full runtime readiness. A runtime test would need PostGIS, valid application secrets and an HTTP health check after startup.
