#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
python3 "${ROOT_DIR}/scripts/local_cluster.py" secrets
"${ROOT_DIR}/scripts/setup-vault.sh"
python3 "${ROOT_DIR}/scripts/local_cluster.py" bridge
