#!/usr/bin/env bash
#
# Stand up FitPub locally end to end: a throwaway PostGIS database plus the chart
# installed from this repository, against whatever Kubernetes context is current
# (kind, minikube, Docker Desktop, ...). Intended for trying the chart out, not
# for production.
#
# Usage:
#   scripts/local-quickstart.sh                 # install into namespace "fitpub"
#   NAMESPACE=demo scripts/local-quickstart.sh   # custom namespace
#   scripts/local-quickstart.sh --port-forward   # also start a port-forward when ready
#
set -euo pipefail

NAMESPACE="${NAMESPACE:-fitpub}"
RELEASE="${RELEASE:-fitpub}"
PORT_FORWARD="false"
[ "${1:-}" = "--port-forward" ] && PORT_FORWARD="true"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

red() { printf '\033[31m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }
bold() { printf '\033[1m%s\033[0m\n' "$1"; }

die() { red "ERROR: $1"; [ -n "${2:-}" ] && printf '  -> %s\n' "$2"; exit 1; }

# --- Preflight: tools -------------------------------------------------------
command -v kubectl >/dev/null 2>&1 || die "kubectl is not installed." "Install it: https://kubernetes.io/docs/tasks/tools/"
command -v helm >/dev/null 2>&1 || die "helm is not installed." "Install it: https://helm.sh/docs/intro/install/"

# --- Preflight: a reachable cluster ----------------------------------------
if ! kubectl cluster-info >/dev/null 2>&1; then
  die "No reachable Kubernetes cluster for the current context." \
      "Start one first, e.g.:  kind create cluster --name fitpub   (or minikube start)"
fi
bold "Using cluster context: $(kubectl config current-context)"

# --- Namespace --------------------------------------------------------------
kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

# --- PostGIS ----------------------------------------------------------------
bold "Deploying throwaway PostGIS into namespace '$NAMESPACE'..."
kubectl apply -n "$NAMESPACE" -f "$REPO_ROOT/examples/postgis-dev.yaml"
kubectl rollout status -n "$NAMESPACE" deployment/postgis --timeout=180s \
  || die "PostGIS did not become ready in time." "Check: kubectl -n $NAMESPACE describe deploy/postgis"

# --- Chart ------------------------------------------------------------------
bold "Installing the FitPub chart from $REPO_ROOT/charts/fitpub ..."
if ! helm upgrade --install "$RELEASE" "$REPO_ROOT/charts/fitpub" \
      --namespace "$NAMESPACE" \
      --values "$REPO_ROOT/examples/development-values.yaml" \
      --wait --timeout 5m; then
  red "Install did not complete. Most common causes:"
  printf '  - the database is not reachable or is not PostGIS (V1__enable_postgis migration fails)\n'
  printf '  - a secret is shorter than 32 characters\n'
  printf '  - the node has too little memory for the request\n\n'
  printf 'Inspect with:\n'
  printf '  kubectl -n %s get pods\n' "$NAMESPACE"
  printf '  kubectl -n %s logs deploy/%s\n' "$NAMESPACE" "$RELEASE"
  printf '  kubectl -n %s describe pod -l app.kubernetes.io/instance=%s\n' "$NAMESPACE" "$RELEASE"
  exit 1
fi

green "FitPub is up and healthy."
echo
bold "Access it with a port-forward:"
printf '  kubectl -n %s port-forward svc/%s 8080:8080\n' "$NAMESPACE" "$RELEASE"
printf '  open http://localhost:8080\n\n'
bold "Tear everything down with:"
printf '  scripts/local-teardown.sh\n'

if [ "$PORT_FORWARD" = "true" ]; then
  echo
  bold "Starting port-forward on http://localhost:8080 (Ctrl-C to stop)..."
  exec kubectl -n "$NAMESPACE" port-forward "svc/$RELEASE" 8080:8080
fi
