#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
helm upgrade --install local-ingress traefik --repo https://traefik.github.io/charts \
    --version 37.1.1 --namespace ingress-system --create-namespace \
    --kube-context kind-airflow-local --set service.type=NodePort \
    --set ports.web.nodePort=30080 --set ports.websecure.nodePort=30443 \
    --set ports.web.redirections.entryPoint.to=websecure \
    --set ports.web.redirections.entryPoint.port=443 \
    --wait --timeout 5m
kubectl --context kind-airflow-local apply -f "${ROOT_DIR}/k8s/ingress/airflow-ingress.yaml"
