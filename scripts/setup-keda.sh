#!/usr/bin/env bash
# ==============================================================================
# Setup KEDA (Kubernetes Event-driven Autoscaling) for Airflow Celery Workers
# Provisions KEDA operator and attaches ScaledObject to scale workers on demand.
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="airflow"
KEDA_NAMESPACE="keda"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}=== Setting up KEDA Worker Autoscaler ===${NC}"

# 1. Install KEDA operator if not already deployed
if ! helm list -n "${KEDA_NAMESPACE}" 2>/dev/null | grep -qx "keda"; then
    echo "Adding KEDA Helm repository..."
    helm repo add kedacore https://kedacore.github.io/charts 2>/dev/null || true
    helm repo update kedacore

    echo "Deploying KEDA operator to namespace '${KEDA_NAMESPACE}'..."
    helm upgrade --install keda kedacore/keda \
        --namespace "${KEDA_NAMESPACE}" \
        --create-namespace \
        --wait --timeout=120s
else
    echo "KEDA operator is already installed in namespace '${KEDA_NAMESPACE}'."
fi

# 2. Apply ScaledObject and TriggerAuthentication in Airflow namespace
echo "Applying Airflow worker ScaledObject and TriggerAuthentication..."
kubectl apply -f "${ROOT_DIR}/k8s/keda/keda-scaledobject.yaml"

echo -e "${GREEN}KEDA Worker Autoscaler successfully configured!${NC}"
