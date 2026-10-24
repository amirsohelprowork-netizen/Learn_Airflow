#!/usr/bin/env bash
# Tear down the local KinD Kubernetes cluster
set -euo pipefail

CLUSTER_NAME="airflow-local"

echo "=== Deleting KinD cluster '${CLUSTER_NAME}' ==="
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
    kind delete cluster --name "${CLUSTER_NAME}"
    echo "KinD cluster '${CLUSTER_NAME}' deleted successfully."
else
    echo "KinD cluster '${CLUSTER_NAME}' is not currently running."
fi

echo "=== Stopping external infrastructure containers ==="
docker stop airflow-keycloak airflow-openldap airflow-phpldapadmin airflow-postgres airflow-redis airflow-vault airflow-minio airflow-artifactory 2>/dev/null || true
echo "All external containers stopped. Volumes and metadata are preserved."
