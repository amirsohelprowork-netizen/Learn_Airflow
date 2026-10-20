#!/usr/bin/env bash
# ==============================================================================
# Setup & Seed External S3 Storage for Airflow
# Runs Adobe S3Mock as an external Docker container outside KinD cluster
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S3_CONTAINER="airflow-s3"
S3_PORT="9090"
S3_ENDPOINT="http://localhost:${S3_PORT}"
NAMESPACE="airflow"

# Color helpers
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}=== 1. Checking External S3 Container ===${NC}"
if ! docker ps --filter "name=^/${S3_CONTAINER}$" --format '{{.Names}}' | grep -qx "${S3_CONTAINER}"; then
    if docker ps -a --filter "name=^/${S3_CONTAINER}$" --format '{{.Names}}' | grep -qx "${S3_CONTAINER}"; then
        echo "Starting existing '${S3_CONTAINER}' container..."
        docker start "${S3_CONTAINER}"
    else
        echo "Launching new external S3 container '${S3_CONTAINER}' on port ${S3_PORT}..."
        docker run -d \
            --name "${S3_CONTAINER}" \
            --restart unless-stopped \
            -p "${S3_PORT}:9090" \
            -e initialBuckets=airflow-logs \
            adobe/s3mock:latest
    fi
else
    echo "S3 container '${S3_CONTAINER}' is already running."
fi

echo "Waiting for S3 to be ready at ${S3_ENDPOINT}..."
for i in {1..30}; do
    if curl -s -f "${S3_ENDPOINT}/" >/dev/null 2>&1; then
        echo -e "${GREEN}S3 storage is responsive.${NC}"
        break
    fi
    sleep 1
done

echo "Ensuring 'airflow-logs' bucket exists..."
curl -s -X PUT "${S3_ENDPOINT}/airflow-logs" >/dev/null 2>&1 || true

echo -e "${CYAN}=== 2. Connecting S3 to Kubernetes KinD Cluster ===${NC}"
if kubectl cluster-info >/dev/null 2>&1; then
    kubectl apply -f "${ROOT_DIR}/k8s/s3/service.yaml"
    echo -e "${GREEN}S3 service & endpoints mapped in namespace '${NAMESPACE}'.${NC}"
fi

echo -e "${CYAN}=== 3. Checking S3 Browser Web UI Container ===${NC}"
UI_CONTAINER="airflow-s3-ui"
UI_PORT="9001"
DOCKER_GW=$(ip -4 addr show docker0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "172.17.0.1")

if ! docker ps --filter "name=^/${UI_CONTAINER}$" --format '{{.Names}}' | grep -qx "${UI_CONTAINER}"; then
    if docker ps -a --filter "name=^/${UI_CONTAINER}$" --format '{{.Names}}' | grep -qx "${UI_CONTAINER}"; then
        echo "Starting existing '${UI_CONTAINER}' container..."
        docker start "${UI_CONTAINER}"
    else
        echo "Launching S3 Browser Web UI on port ${UI_PORT}..."
        docker run -d \
            --name "${UI_CONTAINER}" \
            --restart unless-stopped \
            -p "${UI_PORT}:3000" \
            -e S3_ENDPOINT_URL="http://${DOCKER_GW}:${S3_PORT}" \
            -e S3_BUCKET_NAME="airflow-logs" \
            -e S3_ACCESS_KEY_ID="mock_access_key" \
            -e S3_SECRET_ACCESS_KEY="mock_secret_key" \
            -e S3_REGION="us-east-1" \
            -e S3_FORCE_PATH_STYLE="true" \
            lstsystems/s3n-browser:latest
    fi
else
    echo "S3 Browser Web UI '${UI_CONTAINER}' is already running."
fi

echo -e "${GREEN}S3 Browser Web UI is available at: http://localhost:${UI_PORT}${NC}"

