#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# DAGs, configuration, constraints and tests all contribute to this immutable tag.
docker build -t "learn-airflow:${AIRFLOW_IMAGE_TAG}" "${ROOT_DIR}"
