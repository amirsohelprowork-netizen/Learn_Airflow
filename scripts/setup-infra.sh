#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
"${ROOT_DIR}/scripts/setup-tools.sh"
if ! docker network inspect kind >/dev/null 2>&1; then
    docker network create kind >/dev/null
fi
"${ROOT_DIR}/scripts/build-image.sh"
"${ROOT_DIR}/scripts/setup-db-redis.sh"
"${ROOT_DIR}/scripts/setup-ldap.sh"
"${ROOT_DIR}/scripts/setup-keycloak.sh"
"${ROOT_DIR}/scripts/setup-s3.sh"
ensure_container airflow-local-mailpit -p 127.0.0.1:8025:8025 \
    -v airflow-local-mailpit-data:/data -e MP_DATABASE=/data/mailpit.db \
    axllent/mailpit:v1.27@sha256:e22dce5b36f93c77082e204a3942fb6b283b7896e057458400a4c88344c3df68
# Vault must be configured after the cluster exists; see reconcile-cluster.sh.
