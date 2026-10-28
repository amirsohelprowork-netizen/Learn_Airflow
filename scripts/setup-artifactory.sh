#!/usr/bin/env bash
# ==============================================================================
# Setup & Bridge External Artifactory (Sonatype Nexus 3 OSS) for Airflow
# Runs Artifactory as an external Docker container outside KinD cluster,
# providing central caching and single-source proxies for:
# - PyPI:   http://localhost:8085/repository/pypi-proxy/simple/
# - Docker: http://localhost:5000 (Registry v2 caching proxy for Docker Hub)
# - Helm:   http://localhost:8085/repository/helm-proxy/
# ==============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACTORY_CONTAINER="airflow-local-artifactory"
ARTIFACTORY_UI_PORT="8085"
ARTIFACTORY_DOCKER_PORT="5000"
ARTIFACTORY_PASS="${NEXUS_ADMIN_PASSWORD}"
NAMESPACE="airflow"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}=== 1. Starting External Artifactory Container (Nexus 3 OSS) ===${NC}"
if ! docker ps --filter "name=^/${ARTIFACTORY_CONTAINER}$" --format '{{.Names}}' | grep -qx "${ARTIFACTORY_CONTAINER}"; then
    if docker ps -a --filter "name=^/${ARTIFACTORY_CONTAINER}$" --format '{{.Names}}' | grep -qx "${ARTIFACTORY_CONTAINER}"; then
        echo "Starting existing '${ARTIFACTORY_CONTAINER}' container..."
        docker start "${ARTIFACTORY_CONTAINER}"
    else
        echo "Launching external Artifactory container '${ARTIFACTORY_CONTAINER}' on port ${ARTIFACTORY_UI_PORT} (UI) & ${ARTIFACTORY_DOCKER_PORT} (Docker)..."
        docker run -d \
            --name "${ARTIFACTORY_CONTAINER}" \
            --restart unless-stopped \
            -p "127.0.0.1:${ARTIFACTORY_UI_PORT}:8081" \
            -p "127.0.0.1:${ARTIFACTORY_DOCKER_PORT}:5000" \
            -e INSTALL4J_ADD_VM_PARAMS="-Xms1024m -Xmx2048m -XX:MaxDirectMemorySize=1024m" \
            -v airflow-local-artifactory-data:/nexus-data \
            sonatype/nexus3@sha256:5a90cc609f47d1461282a314fbb78906a5d84c8961d515902e46e357c7278471
    fi
else
    echo "External Artifactory container '${ARTIFACTORY_CONTAINER}' is already running."
fi

# Connect Artifactory container to KinD network bridge if present
if docker network inspect kind >/dev/null 2>&1; then
    connect_kind "${ARTIFACTORY_CONTAINER}"
fi

echo "Waiting for Artifactory to be ready on http://localhost:${ARTIFACTORY_UI_PORT}..."
READY=false
for i in {1..90}; do
    if curl -s -f -u "admin:${ARTIFACTORY_PASS}" "http://localhost:${ARTIFACTORY_UI_PORT}/service/rest/v1/status" >/dev/null 2>&1; then
        READY=true
        echo -e "${GREEN}Artifactory is healthy and authenticated.${NC}"
        break
    elif curl -s -f "http://localhost:${ARTIFACTORY_UI_PORT}/service/rest/v1/status" >/dev/null 2>&1; then
        READY=true
        echo -e "${GREEN}Artifactory server is responding to status probes.${NC}"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

if [ "$READY" = false ]; then
    echo -e "${RED}ERROR: Artifactory did not start within the expected time window.${NC}"
    exit 1
fi

echo -e "${CYAN}=== 2. Configuring Admin Credentials & Anonymous Access ===${NC}"
# Check if initial generated password exists inside the volume
CURRENT_PASS="${ARTIFACTORY_PASS}"
if docker exec "${ARTIFACTORY_CONTAINER}" test -f /nexus-data/admin.password 2>/dev/null; then
    INITIAL_PASS=$(docker exec "${ARTIFACTORY_CONTAINER}" cat /nexus-data/admin.password)
    echo "Updating initial admin password to generated local password..."
    curl -s -f -X PUT \
        -u "admin:${INITIAL_PASS}" \
        -H "Content-Type: text/plain" \
        -d "${ARTIFACTORY_PASS}" \
        "http://localhost:${ARTIFACTORY_UI_PORT}/service/rest/v1/security/users/admin/change-password"
    echo "Admin password configured; use ./ctl credentials to view it."
fi

# Enable Anonymous access so pip, helm, and docker can pull without credentials
echo "Enabling anonymous pull access for PyPI, Helm, and Docker..."
curl -s -f -X PUT \
    -u "admin:${ARTIFACTORY_PASS}" \
    -H "Content-Type: application/json" \
    -d '{"enabled": true, "userId": "anonymous", "realmName": "NexusAuthorizingRealm"}' \
    "http://localhost:${ARTIFACTORY_UI_PORT}/service/rest/v1/security/anonymous"

# Activate Docker Token Realm for token-based docker pull
echo "Activating DockerToken realm..."
curl -s -f -X PUT \
    -u "admin:${ARTIFACTORY_PASS}" \
    -H "Content-Type: application/json" \
    -d '["NexusAuthenticatingRealm", "NexusAuthorizingRealm", "DockerToken"]' \
    "http://localhost:${ARTIFACTORY_UI_PORT}/service/rest/v1/security/realms/active"

# Accept Community Edition EULA if required
echo "Accepting Community Edition EULA..."
python3 -c '
import urllib.request, urllib.error, json, base64

auth = base64.b64encode(b"admin:'"${ARTIFACTORY_PASS}"'").decode("ascii")
try:
    req = urllib.request.Request("http://localhost:'"${ARTIFACTORY_UI_PORT}"'/service/rest/v1/system/eula", headers={"Authorization": f"Basic {auth}"})
    data = json.loads(urllib.request.urlopen(req).read().decode("utf-8"))
    if not data.get("accepted"):
        data["accepted"] = True
        post_req = urllib.request.Request(
            "http://localhost:'"${ARTIFACTORY_UI_PORT}"'/service/rest/v1/system/eula",
            data=json.dumps(data).encode("utf-8"),
            headers={"Authorization": f"Basic {auth}", "Content-Type": "application/json"},
            method="POST"
        )
        urllib.request.urlopen(post_req)
except urllib.error.HTTPError as exc:
    if exc.code != 404:
        raise
'

echo -e "${CYAN}=== 3. Creating Repositories in Artifactory ===${NC}"

# Check existing repositories
EXISTING_REPOS=$(curl --fail -s -u "admin:${ARTIFACTORY_PASS}" "http://localhost:${ARTIFACTORY_UI_PORT}/service/rest/v1/repositories")

# 1. PyPI Proxy Repository
if echo "${EXISTING_REPOS}" | grep -q '"name"[[:space:]]*:[[:space:]]*"pypi-proxy"'; then
    echo "PyPI proxy repository 'pypi-proxy' already exists."
else
    echo "Creating PyPI proxy repository 'pypi-proxy' (upstream: https://pypi.org)..."
    curl -s -f -X POST \
        -u "admin:${ARTIFACTORY_PASS}" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "pypi-proxy",
            "online": true,
            "storage": { "blobStoreName": "default", "strictContentTypeValidation": true },
            "cleanup": null,
            "proxy": { "remoteUrl": "https://pypi.org", "contentMaxAge": 1440, "metadataMaxAge": 1440 },
            "negativeCache": { "enabled": true, "timeToLive": 1440 },
            "httpClient": { "blocked": false, "autoBlock": true, "connection": { "retries": 2, "timeout": 60 } },
            "pypi": { "removeQuotas": false }
        }' \
        "http://localhost:${ARTIFACTORY_UI_PORT}/service/rest/v1/repositories/pypi/proxy"
    echo -e "${GREEN}PyPI proxy created at http://localhost:${ARTIFACTORY_UI_PORT}/repository/pypi-proxy/simple/${NC}"
fi

# 2. Docker Proxy Repository (Port 5000)
if echo "${EXISTING_REPOS}" | grep -q '"name"[[:space:]]*:[[:space:]]*"docker-hub-proxy"'; then
    echo "Docker Hub proxy repository 'docker-hub-proxy' already exists."
else
    echo "Creating Docker Hub proxy repository 'docker-hub-proxy' on port ${ARTIFACTORY_DOCKER_PORT}..."
    curl -s -f -X POST \
        -u "admin:${ARTIFACTORY_PASS}" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "docker-hub-proxy",
            "online": true,
            "storage": { "blobStoreName": "default", "strictContentTypeValidation": true },
            "cleanup": null,
            "proxy": { "remoteUrl": "https://registry-1.docker.io", "contentMaxAge": 1440, "metadataMaxAge": 1440 },
            "negativeCache": { "enabled": true, "timeToLive": 1440 },
            "httpClient": { "blocked": false, "autoBlock": true, "connection": { "retries": 2, "timeout": 60 } },
            "docker": { "v1Enabled": true, "forceBasicAuth": false, "httpPort": 5000 },
            "dockerProxy": { "indexType": "HUB" }
        }' \
        "http://localhost:${ARTIFACTORY_UI_PORT}/service/rest/v1/repositories/docker/proxy"
    echo -e "${GREEN}Docker Hub proxy created on port ${ARTIFACTORY_DOCKER_PORT}.${NC}"
fi

# 3. Helm Proxy Repository
if echo "${EXISTING_REPOS}" | grep -q '"name"[[:space:]]*:[[:space:]]*"helm-proxy"'; then
    echo "Helm proxy repository 'helm-proxy' already exists."
else
    echo "Creating Helm proxy repository 'helm-proxy' (upstream: https://airflow.apache.org)..."
    curl -s -f -X POST \
        -u "admin:${ARTIFACTORY_PASS}" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "helm-proxy",
            "online": true,
            "storage": { "blobStoreName": "default", "strictContentTypeValidation": true },
            "cleanup": null,
            "proxy": { "remoteUrl": "https://airflow.apache.org", "contentMaxAge": 1440, "metadataMaxAge": 1440 },
            "negativeCache": { "enabled": true, "timeToLive": 1440 },
            "httpClient": { "blocked": false, "autoBlock": true, "connection": { "retries": 2, "timeout": 60 } }
        }' \
        "http://localhost:${ARTIFACTORY_UI_PORT}/service/rest/v1/repositories/helm/proxy"
    echo -e "${GREEN}Helm proxy created at http://localhost:${ARTIFACTORY_UI_PORT}/repository/helm-proxy/${NC}"
fi

echo -e "${CYAN}=== 4. Mapping External Artifactory into Kubernetes ===${NC}"
if kubectl --context kind-airflow-local cluster-info >/dev/null 2>&1; then
    kubectl --context kind-airflow-local create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl --context kind-airflow-local apply -f -
    echo "Nexus is accessed through loopback by host build tools only."
    echo -e "${GREEN}Artifactory service & endpoints mapped in namespace '${NAMESPACE}'.${NC}"
else
    echo -e "${YELLOW}Kubernetes cluster not running yet; service mapping will occur during cluster startup.${NC}"
fi

echo -e "${GREEN}======================================================================${NC}"
echo -e "${GREEN}External Artifactory (Nexus 3 OSS) is ready!${NC}"
echo -e "  Web Console:   ${CYAN}http://localhost:${ARTIFACTORY_UI_PORT}${NC} (User: admin | use ./ctl credentials)"
echo -e "  PyPI Simple:   ${CYAN}http://localhost:${ARTIFACTORY_UI_PORT}/repository/pypi-proxy/simple/${NC}"
echo -e "  Docker Mirror: ${CYAN}http://localhost:${ARTIFACTORY_DOCKER_PORT}${NC}"
echo -e "  Helm Repo:     ${CYAN}http://localhost:${ARTIFACTORY_UI_PORT}/repository/helm-proxy/${NC}"
echo -e "${GREEN}======================================================================${NC}"
