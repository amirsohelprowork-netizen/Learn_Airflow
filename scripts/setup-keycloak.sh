#!/usr/bin/env bash
# ==============================================================================
# Setup & Bridge External Keycloak Identity Provider for Airflow
# Runs Keycloak as an external Docker container outside KinD cluster,
# matching enterprise architecture where IdP/IAM is a central external service.
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYCLOAK_CONTAINER="airflow-keycloak"
KEYCLOAK_PORT="8081"
NAMESPACE="airflow"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}=== 1. Starting External Keycloak Identity Provider Container ===${NC}"
if ! docker ps --filter "name=^/${KEYCLOAK_CONTAINER}$" --format '{{.Names}}' | grep -qx "${KEYCLOAK_CONTAINER}"; then
    if docker ps -a --filter "name=^/${KEYCLOAK_CONTAINER}$" --format '{{.Names}}' | grep -qx "${KEYCLOAK_CONTAINER}"; then
        echo "Starting existing '${KEYCLOAK_CONTAINER}' container..."
        docker start "${KEYCLOAK_CONTAINER}"
    else
        echo "Launching external Keycloak container '${KEYCLOAK_CONTAINER}' on port ${KEYCLOAK_PORT}..."
        docker run -d \
            --name "${KEYCLOAK_CONTAINER}" \
            --restart unless-stopped \
            -p "${KEYCLOAK_PORT}:8080" \
            -e KEYCLOAK_ADMIN=admin \
            -e KEYCLOAK_ADMIN_PASSWORD=admin \
            -e KC_HTTP_PORT=8080 \
            -e KC_HOSTNAME="http://localhost:${KEYCLOAK_PORT}" \
            -e KC_HOSTNAME_STRICT="false" \
            -e KC_HOSTNAME_BACKCHANNEL_DYNAMIC="true" \
            -e KC_HTTP_ENABLED="true" \
            -e KC_HEALTH_ENABLED="true" \
            -v "${ROOT_DIR}/k8s/keycloak/realm-airflow.json:/opt/keycloak/data/import/airflow-realm.json:ro" \
            quay.io/keycloak/keycloak:26.0.0 \
            start-dev --import-realm
    fi
else
    echo "External Keycloak container '${KEYCLOAK_CONTAINER}' is already running."
fi

# Connect Keycloak container to KinD network if present
if docker network inspect kind >/dev/null 2>&1; then
    docker network connect kind "${KEYCLOAK_CONTAINER}" 2>/dev/null || true
fi

echo "Waiting for Keycloak to be ready at http://localhost:${KEYCLOAK_PORT}..."
for i in {1..60}; do
    if curl -s -f "http://localhost:${KEYCLOAK_PORT}/realms/airflow/.well-known/openid-configuration" >/dev/null 2>&1; then
        echo -e "${GREEN}Keycloak is healthy and realm 'airflow' is ready.${NC}"
        break
    fi
    sleep 2
done

echo -e "${CYAN}=== 2. Mapping External Keycloak into Kubernetes ===${NC}"
if kubectl cluster-info >/dev/null 2>&1; then
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f "${ROOT_DIR}/k8s/keycloak/service.yaml"
    echo -e "${GREEN}Service 'keycloak' mapped in namespace '${NAMESPACE}' to external host container.${NC}"
else
    echo -e "${YELLOW}Kubernetes cluster not detected yet; skipping k8s service mapping.${NC}"
fi

echo -e "${GREEN}External Keycloak Identity Provider is ready!${NC}"
