#!/usr/bin/env bash
# ==============================================================================
# Setup & Bridge External PostgreSQL & Redis for Airflow
# Runs PostgreSQL 16 and Redis 7 as external services outside the KinD cluster,
# matching enterprise architecture where stateful services live outside compute.
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POSTGRES_CONTAINER="airflow-postgres"
REDIS_CONTAINER="airflow-redis"
NAMESPACE="airflow"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}=== 1. Starting External PostgreSQL 16 Service ===${NC}"
if ! docker ps --filter "name=^/${POSTGRES_CONTAINER}$" --format '{{.Names}}' | grep -qx "${POSTGRES_CONTAINER}"; then
    if docker ps -a --filter "name=^/${POSTGRES_CONTAINER}$" --format '{{.Names}}' | grep -qx "${POSTGRES_CONTAINER}"; then
        echo "Starting existing '${POSTGRES_CONTAINER}' container..."
        docker start "${POSTGRES_CONTAINER}"
    else
        echo "Launching external PostgreSQL 16 container '${POSTGRES_CONTAINER}'..."
        docker run -d \
            --name "${POSTGRES_CONTAINER}" \
            --restart unless-stopped \
            -p 5432:5432 \
            -e POSTGRES_USER=airflow \
            -e POSTGRES_PASSWORD=airflow \
            -e POSTGRES_DB=airflow \
            -v airflow-postgres-data:/var/lib/postgresql/data \
            postgres:16-alpine
    fi
else
    echo "External PostgreSQL container '${POSTGRES_CONTAINER}' is already running."
fi

echo -e "${CYAN}=== 2. Starting External Redis 7 Broker Service ===${NC}"
if ! docker ps --filter "name=^/${REDIS_CONTAINER}$" --format '{{.Names}}' | grep -qx "${REDIS_CONTAINER}"; then
    if docker ps -a --filter "name=^/${REDIS_CONTAINER}$" --format '{{.Names}}' | grep -qx "${REDIS_CONTAINER}"; then
        echo "Starting existing '${REDIS_CONTAINER}' container..."
        docker start "${REDIS_CONTAINER}"
    else
        echo "Launching external Redis 7 container '${REDIS_CONTAINER}'..."
        docker run -d \
            --name "${REDIS_CONTAINER}" \
            --restart unless-stopped \
            -p 6379:6379 \
            -v airflow-redis-data:/data \
            redis:7-alpine
    fi
else
    echo "External Redis container '${REDIS_CONTAINER}' is already running."
fi

echo "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
    if docker exec "${POSTGRES_CONTAINER}" pg_isready -U airflow -d airflow >/dev/null 2>&1; then
        echo -e "${GREEN}PostgreSQL is healthy and accepting connections.${NC}"
        break
    fi
    sleep 1
done

echo "Waiting for Redis to be ready..."
for i in {1..30}; do
    if docker exec "${REDIS_CONTAINER}" redis-cli ping | grep -q "PONG"; then
        echo -e "${GREEN}Redis is healthy and accepting connections.${NC}"
        break
    fi
    sleep 1
done

echo -e "${CYAN}=== 3. Mapping External DB & Broker into Kubernetes ===${NC}"
if kubectl cluster-info >/dev/null 2>&1; then
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f "${ROOT_DIR}/k8s/postgres/service.yaml"
    kubectl apply -f "${ROOT_DIR}/k8s/redis/service.yaml"
    echo -e "${GREEN}Services 'postgres' and 'redis' mapped in namespace '${NAMESPACE}'.${NC}"

    # Create connection secrets for Airflow Helm chart
    kubectl create secret generic airflow-metadata-secret \
        --from-literal=connection="postgresql+psycopg2://airflow:airflow@postgres.airflow.svc.cluster.local:5432/airflow" \
        -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

    kubectl create secret generic airflow-broker-secret \
        --from-literal=connection="redis://redis.airflow.svc.cluster.local:6379/0" \
        -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    echo -e "${GREEN}Kubernetes secrets 'airflow-metadata-secret' and 'airflow-broker-secret' created.${NC}"
else
    echo -e "${YELLOW}Kubernetes cluster not detected yet; skipping k8s service mapping.${NC}"
fi

echo -e "${GREEN}External Database and Broker services are ready!${NC}"
