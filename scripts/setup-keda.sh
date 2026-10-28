#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
helm upgrade --install keda keda --repo https://kedacore.github.io/charts \
    --version "${KEDA_CHART_VERSION}" --namespace keda --create-namespace \
    --kube-context kind-airflow-local --wait --timeout 5m
# Airflow chart generates its ScaledObject using the configured worker concurrency.
