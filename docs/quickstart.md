# Quick Start (local)

FitPub on a local cluster in a few minutes. This is the kick-the-tires path - a
throwaway PostGIS with trivial credentials and no persistence, so do not point your
real data at it. For the real thing see
[`examples/production-values.yaml`](../examples/production-values.yaml) and the
[publishing](publishing.md) / [upgrade](upgrade-notes.md) docs.

## Prerequisites

- A local Kubernetes cluster. Any of these works:
  - [kind](https://kind.sigs.k8s.io/): `kind create cluster --name fitpub`
  - [minikube](https://minikube.sigs.k8s.io/): `minikube start`
  - Docker Desktop with Kubernetes enabled
- [`kubectl`](https://kubernetes.io/docs/tasks/tools/) and [`helm`](https://helm.sh/docs/intro/install/) 3.8+
- ~2 GiB of free memory for the cluster (dev values request 1536Mi for FitPub)

> FitPub needs PostgreSQL **with the PostGIS extension** - a plain PostgreSQL
> database is not enough. The quickstart uses the `postgis/postgis` image so this
> is handled for you.

## One command

From the repository root:

```bash
scripts/local-quickstart.sh
```

It checks your tools and cluster, deploys PostGIS, installs the chart with
[`examples/development-values.yaml`](../examples/development-values.yaml), waits
until the pod is healthy, and prints how to reach it. Add `--port-forward` to
open the port-forward automatically once it is ready.

When it finishes:

```bash
kubectl -n fitpub port-forward svc/fitpub 8080:8080
# then open http://localhost:8080
```

Tear it all down again with:

```bash
scripts/local-teardown.sh
```

## Manual steps

If you prefer to run each step yourself:

```bash
# 1. A cluster (skip if you already have one)
kind create cluster --name fitpub
kubectl create namespace fitpub

# 2. Throwaway PostGIS (credentials match the dev values below)
kubectl apply -n fitpub -f examples/postgis-dev.yaml
kubectl -n fitpub rollout status deploy/postgis

# 3. The chart, from this repository
helm upgrade --install fitpub ./charts/fitpub \
  --namespace fitpub \
  --values examples/development-values.yaml \
  --wait --timeout 5m

# 4. Reach it
kubectl -n fitpub port-forward svc/fitpub 8080:8080
# open http://localhost:8080
```

## Verify it works

```bash
# Pod should be Running and 1/1 Ready
kubectl -n fitpub get pods -l app.kubernetes.io/instance=fitpub

# Login page should return HTTP 200 once the web stack is up (matches chart probes on FitPub 1.1.1).
# The FitPub image is a minimal JRE - use a throwaway curl pod, not kubectl exec curl.
kubectl -n fitpub run fitpub-login-check \
  --image=curlimages/curl:8.11.1 \
  --restart=Never \
  --rm \
  -i \
  --command -- curl -fsS -o /dev/null -w 'HTTP:%{http_code}\n' http://fitpub:8080/login
```

## Troubleshooting

Most failures surface either as a clear `helm install` error (the chart validates
your values up front) or as a pod that never becomes Ready. Common cases:

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `helm install` fails with `FITPUB_DATABASE_URL ... must be a JDBC PostgreSQL URL` | DB URL is missing the `jdbc:postgresql://` prefix | Use `jdbc:postgresql://host:5432/fitpub` |
| `helm install` fails with `FITPUB_JWT_SECRET is N characters ... at least 32` | Secret too short | `openssl rand -base64 48` and set it |
| `helm install` fails mentioning a "known placeholder value" | Secret left at an example/default placeholder | Generate a real secret as above |
| Pod stuck `0/1`, logs show Flyway / `extension "postgis" is not available` | Database is plain PostgreSQL, not PostGIS | Use a PostGIS-enabled database (the quickstart's `postgis/postgis` image) |
| Pod `CrashLoopBackOff`, logs show datasource / connection refused | App cannot reach the database | Check `FITPUB_DATABASE_URL` host/port and that PostGIS is Ready |
| Pod `Pending`, events show `Insufficient memory` | Node too small for the memory request | Lower `resources.requests.memory` or raise `MaxRAMPercentage` via `JAVA_TOOL_OPTIONS` (dev values use 1536Mi) |
| `ImagePullBackOff` | Registry unreachable or wrong tag | Confirm `codeberg.org/fitpub/fitpub:<tag>` exists and the node has internet |
| Pod Ready but registration emails never arrive | No SMTP configured | Set `FITPUB_MAIL_*`, or gate signups with `FITPUB_REGISTRATION_PASSWORD` |

If a pod will not start at all and you need to look inside the container, enable
diagnostic mode so probes and the entrypoint do not get in the way:

```bash
helm upgrade fitpub ./charts/fitpub -n fitpub --reuse-values \
  --set diagnosticMode.enabled=true
kubectl -n fitpub exec -it $(kubectl -n fitpub get pod -l app.kubernetes.io/instance=fitpub -o jsonpath='{.items[0].metadata.name}') -- sh
# ... then turn it back off:
helm upgrade fitpub ./charts/fitpub -n fitpub --reuse-values \
  --set diagnosticMode.enabled=false
```
