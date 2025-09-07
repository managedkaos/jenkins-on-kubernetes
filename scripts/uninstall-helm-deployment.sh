#!/usr/bin/env bash
set -euo pipefail

export NS=jenkins

RELEASE="${RELEASE:-jenkins-helm}"

command -v helm >/dev/null 2>&1 || { echo "helm not found in PATH"; exit 1; }

echo "==> Uninstalling Helm release '$RELEASE' from namespace: $NS"
if helm status "$RELEASE" -n "$NS" >/dev/null 2>&1; then
  helm uninstall "$RELEASE" -n "$NS"
else
  echo "Release '$RELEASE' not found in namespace '$NS' (skipping)."
fi

kubectl -n "$NS" get all

# Remove any PVCs created by the chart
echo "==> Deleting PVCs labeled with app.kubernetes.io/instance=$RELEASE"
kubectl -n "$NS" get pvc -l app.kubernetes.io/instance="$RELEASE" -o name \
  | xargs -r kubectl -n "$NS" delete

# Final sweep by Helm label (if anything else remains)
kubectl -n "$NS" delete all,cm,secret,sa,role,rolebinding,pvc,ingress \
  -l app.kubernetes.io/instance="$RELEASE" --ignore-not-found || true

echo "==> Helm uninstall complete."

kubectl -n "$NS" get all
