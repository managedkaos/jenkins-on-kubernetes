#!/bin/bash -e

export NS=jenkins

# Prompt the user to continue or exit
echo "This will delete and recreate the Jenkins deployment in the '$NS' namespace."
read -rp "Do you want to continue? (y/n): " choice

if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    echo "Operation cancelled."
    exit 0
fi

set -x

kubectl -n "$NS" delete deploy jenkins-yaml-controller --ignore-not-found
kubectl -n "$NS" delete pvc jenkins-yaml-home --ignore-not-found

kubectl -n "$NS" delete secret jenkins-shared-admin-secret --ignore-not-found
kubectl -n "$NS" create secret generic jenkins-shared-admin-secret \
  --from-literal=JENKINS_ADMIN_ID="$JENKINS_ADMIN_ID" \
  --from-literal=JENKINS_ADMIN_PASSWORD="$JENKINS_ADMIN_PASSWORD"

kubectl -n "$NS" apply -f ./04-persistent-volume-claim.yaml
kubectl -n "$NS" apply -f ./05-configmap-init.yaml
kubectl -n "$NS" apply -f ./06-deployment.yaml
kubectl -n "$NS" apply -f ./07-service.yaml

kubectl -n "$NS" rollout status deployment/jenkins-yaml-controller
kubectl -n "$NS" logs deploy/jenkins-yaml-controller
