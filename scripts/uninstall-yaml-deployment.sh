#!/usr/bin/env bash
set -euo pipefail

export NS=jenkins

YAML_DIR="${YAML_DIR:-./yaml-config}"

echo "==> Uninstalling YAML-based Jenkins from namespace: $NS"
echo "Using YAML_DIR: $YAML_DIR"

kubectl -n "$NS" get all

# Core workload first
kubectl -n "$NS" delete -f "$YAML_DIR/07-service.yaml" --ignore-not-found
kubectl -n "$NS" delete -f "$YAML_DIR/06-deployment.yaml" --ignore-not-found

# Config (plugins + init)
kubectl -n "$NS" delete -f "$YAML_DIR/05-configmap-init.yaml" --ignore-not-found

# Storage (⚠️ deletes Jenkins data for YAML install)
kubectl -n "$NS" delete -f "$YAML_DIR/04-persistent-volume-claim.yaml" --ignore-not-found

# RBAC + SA
kubectl -n "$NS" delete -f "$YAML_DIR/03-role-binding.yaml" --ignore-not-found
kubectl -n "$NS" delete -f "$YAML_DIR/02-role.yaml" --ignore-not-found
kubectl -n "$NS" delete -f "$YAML_DIR/01-service-account.yaml" --ignore-not-found

# Final sweep by label (just in case)
kubectl -n "$NS" delete all,cm,sa,role,rolebinding,pvc,ingress \
  -l app.kubernetes.io/name=jenkins-yaml --ignore-not-found

echo "==> YAML uninstall complete."

kubectl -n "$NS" get all
