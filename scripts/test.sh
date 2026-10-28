#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:-}" == --static ]]; then
    python3 -m unittest discover "${ROOT_DIR}/tests" -v
    exit
fi
tag="$(python3 "${ROOT_DIR}/scripts/local_config.py" tag)"
if ! docker image inspect "learn-airflow:${tag}" >/dev/null 2>&1; then
    "${ROOT_DIR}/scripts/build-image.sh"
fi
docker run --rm --entrypoint python3 -e AIRFLOW_REQUIRE_RUNTIME=1 \
    -e PYTHONPATH=/opt/airflow/config "learn-airflow:${tag}" \
    -m unittest discover /opt/airflow/tests -v
