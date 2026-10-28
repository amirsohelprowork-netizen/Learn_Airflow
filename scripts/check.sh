#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
python3 -m compileall -q config dags scripts tests
for file in ctl scripts/*.sh; do bash -n "$file"; done
export TF_DATA_DIR="$(mktemp -d)"
trap 'rm -rf "$TF_DATA_DIR"' EXIT
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false -input=false
terraform -chdir=terraform validate
"${ROOT_DIR}/scripts/validate-manifests.sh"
"${ROOT_DIR}/scripts/test.sh"
