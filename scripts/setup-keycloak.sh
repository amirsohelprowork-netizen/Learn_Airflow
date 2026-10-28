#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
ensure_container airflow-local-keycloak \
    -p 127.0.0.1:8443:8443 \
    -e KC_BOOTSTRAP_ADMIN_USERNAME=admin -e KC_BOOTSTRAP_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD}" \
    -e KC_DB=postgres -e KC_DB_URL=jdbc:postgresql://airflow-local-postgres:5432/keycloak \
    -e KC_DB_USERNAME=keycloak -e KC_DB_PASSWORD="${KEYCLOAK_DB_PASSWORD}" \
    -e KC_HOSTNAME=https://localhost:8443 -e KC_HOSTNAME_BACKCHANNEL_DYNAMIC=true \
    -e KC_HTTP_ENABLED=false -e KC_HEALTH_ENABLED=true \
    -e KC_HTTPS_CERTIFICATE_FILE=/opt/keycloak/tls/server.crt \
    -e KC_HTTPS_CERTIFICATE_KEY_FILE=/opt/keycloak/tls/server.key \
    -v "${ROOT_DIR}/.local/tls/server.crt:/opt/keycloak/tls/server.crt:ro" \
    -v "${ROOT_DIR}/.local/tls/server.key:/opt/keycloak/tls/server.key:ro" \
    -v "${ROOT_DIR}/.local/realm-airflow.json:/opt/keycloak/data/import/airflow-realm.json:ro" \
    quay.io/keycloak/keycloak:26.0.0@sha256:db0d0f2c2eee8618a37a50e04affb69823e56687b4d1b676a847a4b85de62178 start --import-realm
wait_for Keycloak 90 curl --fail --silent --cacert "${ROOT_DIR}/.local/tls/ca.crt" \
    https://localhost:8443/realms/airflow/.well-known/openid-configuration

python3 "${ROOT_DIR}/scripts/configure_keycloak.py"
