#!/usr/bin/env bash
# A scan may download the public vulnerability database; it does not upload code.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tag="$(python3 "${ROOT_DIR}/scripts/local_config.py" tag)"
image="${1:-learn-airflow:${tag}}"
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    -v airflow-local-trivy-cache:/root/.cache/ \
    aquasec/trivy:0.67.2@sha256:e2b22eac59c02003d8749f5b8d9bd073b62e30fefaef5b7c8371204e0a4b0c08 image --scanners vuln --severity CRITICAL,HIGH \
    --ignore-unfixed --exit-code 1 "$image"
