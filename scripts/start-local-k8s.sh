#!/usr/bin/env bash
# All services run locally. Initial image/chart downloads require internet access.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
"${ROOT_DIR}/scripts/setup-tools.sh"
for tool in docker kind kubectl helm openssl python3; do
    command -v "$tool" >/dev/null || { echo "Missing prerequisite: $tool" >&2; exit 1; }
done
"${ROOT_DIR}/scripts/setup-infra.sh"
if ! kind get clusters | grep -qx airflow-local; then
    kind create cluster --config "${ROOT_DIR}/k8s/kind-cluster.yaml" --wait 180s
else
    docker start airflow-local-control-plane >/dev/null
    wait_for Kubernetes 90 kubectl --context kind-airflow-local get nodes
fi
"${ROOT_DIR}/scripts/reconcile-cluster.sh"
"${ROOT_DIR}/scripts/setup-ingress.sh"
"${ROOT_DIR}/scripts/setup-keda.sh"
"${ROOT_DIR}/scripts/deploy-airflow.sh"
"${ROOT_DIR}/scripts/setup-observability.sh"
echo "Local stack ready. Airflow: https://localhost; Keycloak: https://localhost:8443"
echo "Alert inbox: http://localhost:8025; credentials: ./ctl credentials"
echo "Trust .local/tls/ca.crt in your browser for local HTTPS. See docs/LOCAL_SETUP.md."
