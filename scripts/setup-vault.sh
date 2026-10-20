#!/usr/bin/env bash
# ==============================================================================
# Setup & Seed External HashiCorp Vault for Airflow
# Runs HashiCorp Vault as an external Docker container outside KinD cluster
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_CONTAINER="airflow-vault"
VAULT_PORT="8200"
VAULT_ADDR="http://localhost:${VAULT_PORT}"
VAULT_TOKEN="airflow-vault-root-token-2026"
NAMESPACE="airflow"

# Color helpers
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}=== 1. Checking External HashiCorp Vault Container ===${NC}"
if ! docker ps --filter "name=^/${VAULT_CONTAINER}$" --format '{{.Names}}' | grep -qx "${VAULT_CONTAINER}"; then
    if docker ps -a --filter "name=^/${VAULT_CONTAINER}$" --format '{{.Names}}' | grep -qx "${VAULT_CONTAINER}"; then
        echo "Starting existing '${VAULT_CONTAINER}' container..."
        docker start "${VAULT_CONTAINER}"
    else
        echo "Launching new external HashiCorp Vault container '${VAULT_CONTAINER}' on port ${VAULT_PORT}..."
        docker run -d \
            --name "${VAULT_CONTAINER}" \
            --restart unless-stopped \
            -p "${VAULT_PORT}:${VAULT_PORT}" \
            -e VAULT_DEV_ROOT_TOKEN_ID="${VAULT_TOKEN}" \
            -e VAULT_DEV_LISTEN_ADDRESS="0.0.0.0:${VAULT_PORT}" \
            -e VAULT_UI="true" \
            hashicorp/vault:1.15.6
    fi
else
    echo "HashiCorp Vault container '${VAULT_CONTAINER}' is already running."
fi

echo "Waiting for Vault to be ready at ${VAULT_ADDR}..."
for i in {1..30}; do
    if curl -s -f "${VAULT_ADDR}/v1/sys/health" >/dev/null 2>&1; then
        echo -e "${GREEN}Vault is healthy and responsive.${NC}"
        break
    fi
    sleep 1
done

echo -e "${CYAN}=== 2. Connecting Vault to Kubernetes KinD Cluster ===${NC}"
if kubectl cluster-info >/dev/null 2>&1; then
    kubectl apply -f "${ROOT_DIR}/k8s/vault/service.yaml"
    echo -e "${GREEN}Vault service & endpoints mapped in namespace '${NAMESPACE}'.${NC}"
else
    echo -e "${YELLOW}Kubernetes cluster not detected yet; skipping k8s service mapping.${NC}"
fi

echo -e "${CYAN}=== 3. Populating Initial Secrets & Variables into Vault ===${NC}"
# Use Python helper to populate Vault KV v2 paths cleanly
python3 -c "
import urllib.request, json

vault_url = '${VAULT_ADDR}'
vault_token = '${VAULT_TOKEN}'

def write_secret(path, data):
    url = f'{vault_url}/v1/secret/data/{path}'
    payload = json.dumps({'data': data}).encode('utf-8')
    req = urllib.request.Request(
        url,
        data=payload,
        headers={'X-Vault-Token': vault_token, 'Content-Type': 'application/json'},
        method='POST'
    )
    try:
        urllib.request.urlopen(req)
        print(f'  [OK] secret/data/{path}')
    except Exception as e:
        print(f'  [ERROR] secret/data/{path}: {e}')

print('Seeding Airflow Variables:')
write_secret('airflow/variables/keycloak_admin_password', {'value': 'admin'})
write_secret('airflow/variables/keycloak_client_secret', {'value': 'airflow-client-secret'})
write_secret('airflow/variables/breakglass_password', {'value': 'ChangeMeInSecret123!'})
write_secret('airflow/variables/alert_recipient', {'value': 'alerts@example.com'})

print('Seeding Airflow Configs (Keys & Parameters):')
write_secret('airflow/config/core/fernet_key', {'value': '2SL0kSlBxSYcpJnwzhBCWFlGf0mxEao2='})
write_secret('airflow/config/webserver/secret_key', {'value': '2SL0kSlBxSYcpJnwzhBCWFlGf0mxEao2'})
write_secret('airflow/config/api/secret_key', {'value': '2SL0kSlBxSYcpJnwzhBCWFlGf0mxEao2'})

print('Seeding Airflow Connections:')
write_secret('airflow/connections/postgres_default', {
    'conn_type': 'postgres',
    'host': 'airflow-postgresql.airflow.svc.cluster.local',
    'login': 'postgres',
    'password': 'postgres',
    'port': 5432,
    'schema': 'airflow'
})
write_secret('airflow/connections/smtp_default', {
    'conn_type': 'email',
    'host': 'smtp.gmail.com',
    'login': 'alerts@example.com',
    'port': 587
})
"

echo ""
echo -e "${GREEN}======================================================================${NC}"
echo -e "${GREEN}HashiCorp Vault is running outside the cluster!${NC}"
echo -e "${GREEN}======================================================================${NC}"
echo -e "Vault Web UI:       ${YELLOW}http://localhost:8200${NC}"
echo -e "Root Token:         ${YELLOW}${VAULT_TOKEN}${NC}"
echo -e "In-Cluster Endpoint:${YELLOW}http://vault.airflow.svc.cluster.local:8200${NC}"
echo -e "${GREEN}======================================================================${NC}"
