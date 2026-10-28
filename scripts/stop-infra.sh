#!/usr/bin/env bash
set -euo pipefail
mapfile -t containers < <(docker ps -q --filter 'name=^/airflow-local-')
if ((${#containers[@]})); then docker stop "${containers[@]}"; fi
