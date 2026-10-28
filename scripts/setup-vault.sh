#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cat > "${ROOT_DIR}/.local/vault.hcl" <<'EOF'
ui = true
disable_mlock = true
api_addr = "https://airflow-local-vault:8200"
cluster_addr = "https://airflow-local-vault:8201"
storage "raft" {
  path = "/vault/file"
  node_id = "local-vault"
}
listener "tcp" {
  address = "0.0.0.0:8200"
  tls_cert_file = "/vault/tls/server.crt"
  tls_key_file = "/vault/tls/server.key"
}
EOF
chmod 644 "${ROOT_DIR}/.local/vault.hcl"
ensure_container airflow-local-vault -e SKIP_SETCAP=true -p 127.0.0.1:8200:8200 \
    -v airflow-local-vault-data:/vault/file \
    -v "${ROOT_DIR}/.local/vault.hcl:/vault/config/local.hcl:ro" \
    -v "${ROOT_DIR}/.local/tls/server.crt:/vault/tls/server.crt:ro" \
    -v "${ROOT_DIR}/.local/tls/server.key:/vault/tls/server.key:ro" hashicorp/vault:1.15.6@sha256:0450896c43b13879b19442b204ce29dd19b5a10fce43d5cf38af17da20f56f4d server
python3 "${ROOT_DIR}/scripts/local_cluster.py" vault
