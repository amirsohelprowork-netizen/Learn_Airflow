#!/usr/bin/env bash
# Use a project-local, checksum-pinned CLI compatible with Kubernetes 1.34.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)/$(uname -m)" != Linux/x86_64 ]]; then
    echo 'This tested local profile currently supports Linux x86_64.' >&2
    exit 1
fi
mkdir -p "${ROOT_DIR}/.local/bin"
expected=517ab7fc89ddeed5fa65abf71530d90648d9638ef0c4cde22c2c11f8097b8889
binary="${ROOT_DIR}/.local/bin/kind"
if [[ -f "$binary" ]] && [[ "$(sha256sum "$binary" | cut -d ' ' -f1)" == "$expected" ]]; then
    chmod 700 "$binary"
    exit
fi
curl --fail --location --silent --show-error \
    https://kind.sigs.k8s.io/dl/v0.30.0/kind-linux-amd64 -o "${binary}.download"
echo "${expected}  ${binary}.download" | sha256sum --check --status
chmod 700 "${binary}.download"
mv "${binary}.download" "$binary"
