#!/usr/bin/env bash
set -euo pipefail

export NS=jenkins

# Set to 'true' to also delete any cluster PVs bound to this namespace
PURGE_PVS="${PURGE_PVS:-false}"
PURGE_NS="${PURGE_NS:-false}"

echo "==> Removing shared resources in namespace: $NS"

# Shared admin secrets used across installs
kubectl -n "$NS" delete secret jenkins-shared-admin-secret --ignore-not-found
kubectl -n "$NS" delete secret jenkins-admin --ignore-not-found

# Optional: sweep any remaining Jenkins-labeled things (belt & suspenders)
kubectl -n "$NS" delete all,cm,secret,sa,role,rolebinding,pvc,ingress \
  -l app.kubernetes.io/name=jenkins-yaml --ignore-not-found || true
kubectl -n "$NS" delete all,cm,secret,sa,role,rolebinding,pvc,ingress \
  -l app.kubernetes.io/instance=jenkins-helm --ignore-not-found || true

# Optionally delete PVs whose claims live in this namespace (careful!)
if [[ "$PURGE_PVS" == "true" ]]; then
  echo "==> PURGE_PVS=true: deleting PVs bound to namespace '$NS'"
  # Find PVs whose claimRef.namespace matches $NS, then delete them
  kubectl get pv -o jsonpath='{range .items[?(@.spec.claimRef.namespace)]}{.metadata.name}{"\t"}{.spec.claimRef.namespace}{"\n"}{end}' \
    | awk -v ns="$NS" '$2==ns {print $1}' \
    | xargs -r kubectl delete pv
else
  echo "==> Skipping PV deletion (set PURGE_PVS=true to enable)."
fi

# Optionally delete the namespace
if [[ "$PURGE_NS" == "true" ]]; then
  echo "==> Deleting namespace: $NS"
  echo kubectl delete ns "$NS" || true
  echo "==> Namespace deletion may take a moment to finalize."
else
  echo "==> Skipping Namespace deletion (set PURGE_NS=true to enable)."
fi
