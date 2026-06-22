#!/usr/bin/env bash
#
# Remove the local FitPub release and the throwaway PostGIS deployed by
# scripts/local-quickstart.sh. Leaves the cluster itself untouched.
#
set -euo pipefail

NAMESPACE="${NAMESPACE:-fitpub}"
RELEASE="${RELEASE:-fitpub}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

helm uninstall "$RELEASE" --namespace "$NAMESPACE" 2>/dev/null || true
kubectl delete -n "$NAMESPACE" -f "$REPO_ROOT/examples/postgis-dev.yaml" --ignore-not-found
# The uploads PVC is retained by Helm on uninstall; drop it so a re-run starts clean.
kubectl delete pvc -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE" --ignore-not-found

printf 'Done. To also delete the namespace: kubectl delete namespace %s\n' "$NAMESPACE"
