#!/usr/bin/env bash
# Stop compute and services; retain named volumes, certificates and credentials.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if docker container inspect airflow-local-control-plane >/dev/null 2>&1; then
    docker stop airflow-local-control-plane
fi
mapfile -t containers < <(docker ps -q --filter 'name=^/airflow-local-')
if ((${#containers[@]})); then docker stop "${containers[@]}"; fi
echo "Local compute stopped. Data volumes and .local/ are preserved."
