#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
docker volume create airflow-local-minio-data >/dev/null
# The non-root MinIO image needs ownership of a fresh named volume.
docker run --rm --user 0 --entrypoint chown -v airflow-local-minio-data:/data \
    postgres:16-alpine@sha256:721873c34ceb9f8d8fc265984940dc982404c105f19ad51be9fdc5970a6080ea 65532:65532 /data
ensure_container airflow-local-minio -p 127.0.0.1:9001:9001 \
    -v airflow-local-minio-data:/data -e MINIO_ROOT_USER=airflow-local \
    -e MINIO_ROOT_PASSWORD="${MINIO_PASSWORD}" \
    cleanstart/minio@sha256:0b2a75b9cf8382ee1de690407b794e8ddd307fceb18543e7cffb90a5683565b1 \
    server /data --console-address :9001
# Use the S3 API, never mkdir inside MinIO's internal storage layout.
python3 "${ROOT_DIR}/scripts/local_cluster.py" buckets
