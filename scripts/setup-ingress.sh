#!/usr/bin/env bash
# ==============================================================================
# Setup NGINX Ingress Controller & cert-manager TLS for Airflow
# Terminates TLS with automated CA-issued certificates for:
# - airflow.local (Airflow Web UI & API Server)
# - auth.local    (Keycloak SSO Identity Provider)
# - flower.local  (Celery Monitoring)
# - grafana.local (Observability Dashboards)
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="airflow-local"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}=== 1. Ensuring KinD Node Ingress Labels ===${NC}"
kubectl label node "${CLUSTER_NAME}-control-plane" ingress-ready=true --overwrite 2>/dev/null || true

echo -e "${CYAN}=== 2. Deploying cert-manager for TLS Management ===${NC}"
if ! helm list -n cert-manager 2>/dev/null | grep -qx "cert-manager"; then
    echo "Adding Jetstack Helm repository..."
    helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
    helm repo update jetstack

    echo "Installing cert-manager with CRDs..."
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --set crds.enabled=true \
        --wait --timeout=120s
else
    echo "cert-manager is already installed."
fi

echo -e "${CYAN}=== 3. Deploying NGINX Ingress Controller ===${NC}"
if ! kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller >/dev/null 2>&1; then
    echo "Applying NGINX Ingress Controller for KinD..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
fi

echo "Waiting for NGINX Ingress Controller rollout..."
kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=120s 2>/dev/null || true

echo -e "${CYAN}=== 4. Applying ClusterIssuer & Ingress Resources ===${NC}"
kubectl apply -f "${ROOT_DIR}/k8s/ingress/cluster-issuer.yaml"
kubectl apply -f "${ROOT_DIR}/k8s/ingress/airflow-ingress.yaml"

# Retrieve node IP for direct access
NODE_IP=$(docker inspect "${CLUSTER_NAME}-control-plane" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "127.0.0.1")

echo ""
echo -e "${GREEN}======================================================================${NC}"
echo -e "${GREEN}TLS Ingress is fully configured with automated cert-manager CA!${NC}"
echo -e "${GREEN}======================================================================${NC}"
echo "Add the following entry to your /etc/hosts for seamless browser access:"
echo -e "  ${YELLOW}${NODE_IP} airflow.local auth.local flower.local grafana.local prometheus.local${NC}"
echo ""
echo "Secure Endpoints (HTTPS):"
echo -e "  Airflow Web UI:  ${CYAN}https://airflow.local${NC}"
echo -e "  Keycloak SSO:    ${CYAN}https://auth.local${NC}"
echo -e "  Flower UI:       ${CYAN}https://flower.local${NC}"
echo -e "  Grafana UI:      ${CYAN}https://grafana.local${NC}"
echo -e "  Prometheus UI:   ${CYAN}https://prometheus.local${NC}"
echo "======================================================================"
