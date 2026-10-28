#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
"${ROOT_DIR}/scripts/setup-tools.sh"
kind load docker-image "learn-airflow:${AIRFLOW_IMAGE_TAG}" --name airflow-local
python3 "${ROOT_DIR}/scripts/local_cluster.py" migrate
helm upgrade --install airflow airflow --repo https://airflow.apache.org \
    --version "${AIRFLOW_CHART_VERSION}" --namespace airflow \
    --kube-context kind-airflow-local -f "${ROOT_DIR}/values.yaml" \
    --set-string "images.airflow.tag=${AIRFLOW_IMAGE_TAG}" \
    --set-string "defaultAirflowTag=${AIRFLOW_IMAGE_TAG}" \
    --wait --wait-for-jobs --timeout 15m --atomic
kubectl --context kind-airflow-local exec -n airflow deployment/airflow-scheduler -c scheduler -- \
    python3 /opt/airflow/config/bootstrap_roles.py
kubectl --context kind-airflow-local rollout status deployment/airflow-dag-processor -n airflow --timeout=300s
