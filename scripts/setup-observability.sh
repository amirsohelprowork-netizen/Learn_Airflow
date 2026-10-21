#!/usr/bin/env bash
# ==============================================================================
# Setup Prometheus & Grafana Observability Stack for Airflow
# Scrapes Airflow StatsD metrics and displays cluster health in Grafana.
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="observability"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}=== Setting up Observability Stack (Prometheus + Grafana) ===${NC}"

# Apply Prometheus deployment, config, and network policy
echo "Deploying Prometheus..."
kubectl apply -f "${ROOT_DIR}/k8s/observability/prometheus.yaml"

# Apply Grafana deployment, datasources, and pre-baked dashboards
echo "Deploying Grafana..."
kubectl apply -f "${ROOT_DIR}/k8s/observability/grafana.yaml"

echo "Waiting for Prometheus and Grafana rollouts..."
kubectl rollout status deployment/prometheus -n "${NAMESPACE}" --timeout=120s
kubectl rollout status deployment/grafana -n "${NAMESPACE}" --timeout=120s

echo -e "${GREEN}Observability stack is healthy and running!${NC}"
