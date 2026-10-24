#!/usr/bin/env bash
# ==============================================================================
# Setup & Seed External S3 Storage for Airflow
# Runs MinIO Object Storage as an external Docker container outside KinD cluster
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MINIO_CONTAINER="airflow-minio"
MINIO_PORT="9000"
MINIO_CONSOLE_PORT="9001"
MINIO_USER="minioadmin"
MINIO_PASS="minioadmin"
NAMESPACE="airflow"

# Color helpers
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}=== 1. Checking External MinIO Container ===${NC}"
if ! docker ps --filter "name=^/${MINIO_CONTAINER}$" --format '{{.Names}}' | grep -qx "${MINIO_CONTAINER}"; then
    if docker ps -a --filter "name=^/${MINIO_CONTAINER}$" --format '{{.Names}}' | grep -qx "${MINIO_CONTAINER}"; then
        echo "Starting existing '${MINIO_CONTAINER}' container..."
        docker start "${MINIO_CONTAINER}"
    else
        echo "Launching new external MinIO container '${MINIO_CONTAINER}' on ports ${MINIO_PORT}/${MINIO_CONSOLE_PORT}..."
        docker run -d \
            --name "${MINIO_CONTAINER}" \
            --user root \
            --restart unless-stopped \
            -p "${MINIO_PORT}:9000" \
            -p "${MINIO_CONSOLE_PORT}:9001" \
            -v airflow-minio-data:/data \
            -e MINIO_ROOT_USER="${MINIO_USER}" \
            -e MINIO_ROOT_PASSWORD="${MINIO_PASS}" \
            cleanstart/minio:latest server /data --console-address ":9001"
    fi
else
    echo "MinIO container '${MINIO_CONTAINER}' is already running."
fi

# Connect MinIO to KinD network if present
if docker network inspect kind >/dev/null 2>&1; then
    docker network connect kind "${MINIO_CONTAINER}" 2>/dev/null || true
fi

echo "Waiting for MinIO to be ready at http://localhost:${MINIO_PORT}..."
for i in {1..30}; do
    if curl -s -f "http://localhost:${MINIO_PORT}/minio/health/live" >/dev/null 2>&1; then
        echo -e "${GREEN}MinIO storage is responsive.${NC}"
        break
    fi
    sleep 1
done

echo "Ensuring 'airflow-logs' and 'airflow-backups' buckets exist in MinIO..."
docker exec "${MINIO_CONTAINER}" mkdir -p /data/airflow-logs /data/airflow-backups

echo -e "${CYAN}=== 2. Connecting MinIO S3 to Kubernetes KinD Cluster ===${NC}"
if kubectl cluster-info >/dev/null 2>&1; then
    kubectl apply -f "${ROOT_DIR}/k8s/s3/service.yaml"
    echo -e "${GREEN}MinIO S3 service & endpoints mapped in namespace '${NAMESPACE}'.${NC}"
fi

echo -e "${GREEN}MinIO S3 API:     http://localhost:${MINIO_PORT}${NC}"
echo -e "${GREEN}MinIO Web Console: http://localhost:${MINIO_CONSOLE_PORT} (User: ${MINIO_USER} | Pass: ${MINIO_PASS})${NC}"
