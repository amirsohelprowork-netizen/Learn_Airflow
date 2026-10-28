#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
kubectl --context kind-airflow-local apply -f "${ROOT_DIR}/k8s/observability/prometheus.yaml"
kubectl --context kind-airflow-local apply -f "${ROOT_DIR}/k8s/observability/grafana.yaml"
kubectl --context kind-airflow-local rollout status deployment/prometheus -n observability --timeout=300s
kubectl --context kind-airflow-local rollout status deployment/grafana -n observability --timeout=300s
