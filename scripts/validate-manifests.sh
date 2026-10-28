#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
chart_dir="$(mktemp -d)"
trap 'rm -rf "$chart_dir"' EXIT
helm pull airflow --repo https://airflow.apache.org --version 1.22.0 --destination "$chart_dir"
helm lint "${chart_dir}/airflow-1.22.0.tgz" -f "${ROOT_DIR}/values.yaml"
helm template airflow "${chart_dir}/airflow-1.22.0.tgz" --namespace airflow \
    -f "${ROOT_DIR}/values.yaml" > "${chart_dir}/rendered.yaml"
python3 "${ROOT_DIR}/scripts/validate_manifests.py" "${chart_dir}/rendered.yaml"

# Production is a standalone profile: never inherit local endpoints or credentials.
helm lint "${chart_dir}/airflow-1.22.0.tgz" -f "${ROOT_DIR}/deploy/production/values.example.yaml"
helm template airflow "${chart_dir}/airflow-1.22.0.tgz" --namespace airflow \
    -f "${ROOT_DIR}/deploy/production/values.example.yaml" > "${chart_dir}/production.yaml"
python3 "${ROOT_DIR}/scripts/validate_manifests.py" "${chart_dir}/production.yaml" production
