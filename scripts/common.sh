#!/usr/bin/env bash
# Shared local environment. Never source .env or print credentials during startup.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "${ROOT_DIR}/scripts/local_config.py" init
source "${ROOT_DIR}/.local/secrets.env"
export PATH="${ROOT_DIR}/.local/bin:${PATH}"
export AIRFLOW_IMAGE_TAG="${AIRFLOW_IMAGE_TAG:-$(python3 "${ROOT_DIR}/scripts/local_config.py" tag)}"
export AIRFLOW_CHART_VERSION=1.22.0
export KEDA_CHART_VERSION=2.18.1
export AIRFLOW_NAMESPACE=airflow

wait_for() {
    local description="$1" attempts="$2"
    shift 2
    for ((attempt=0; attempt<attempts; attempt++)); do
        if "$@" >/dev/null 2>&1; then return 0; fi
        sleep 2
    done
    echo "ERROR: timed out waiting for ${description}" >&2
    return 1
}

connect_kind() {
    local container="$1"
    if ! docker inspect "$container" --format '{{json .NetworkSettings.Networks}}' | python3 -c 'import json,sys; sys.exit(0 if "kind" in json.load(sys.stdin) else 1)'; then
        docker network connect kind "$container"
    fi
}

ensure_container() {
    local container="$1" fingerprint current
    shift
    fingerprint=$(python3 -c 'import hashlib,json,sys; print(hashlib.sha256(json.dumps(sys.argv[1:]).encode()).hexdigest())' "$@")
    if docker container inspect "$container" >/dev/null 2>&1; then
        current=$(docker inspect "$container" --format '{{index .Config.Labels "local-airflow-spec"}}')
        if [[ "$current" == "$fingerprint" ]]; then
            docker start "$container" >/dev/null
            return
        fi
        echo "Replacing configuration for $container; named data volumes are retained."
        docker stop "$container" >/dev/null
        docker rm "$container" >/dev/null
    fi
    docker run -d --name "$container" --label "local-airflow-spec=$fingerprint" \
        --restart unless-stopped --network kind "$@"
}

apply_secret() {
    # JSON over stdin keeps secret values out of kubectl command arguments.
    python3 "${ROOT_DIR}/scripts/local_cluster.py" secrets
}
