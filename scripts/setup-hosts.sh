#!/usr/bin/env bash
# ==============================================================================
# Helper to configure /etc/hosts for Airflow Lab TLS Ingress
# Maps internal .local hostnames to the KinD control-plane IP.
# ==============================================================================
set -euo pipefail

CLUSTER_NAME="airflow-local"
# In KinD, ports 80 and 443 are mapped to the host (0.0.0.0:80 and 0.0.0.0:443).
# Using 127.0.0.1 ensures permanent stability regardless of Docker container IP reassignments.
HOSTS_IP="127.0.0.1"

HOSTS_LINE="${HOSTS_IP} airflow.local auth.local flower.local grafana.local prometheus.local vault.local minio.local ldap.local artifactory.local"

if grep -q "airflow.local" /etc/hosts; then
    EXISTING_LINE=$(grep "airflow.local" /etc/hosts || true)
    if [[ "${EXISTING_LINE}" == *"${HOSTS_IP} "* ]]; then
        echo "Entry for 'airflow.local' is already up to date in /etc/hosts:"
        echo "  ${EXISTING_LINE}"
        exit 0
    else
        echo "Stale entry found in /etc/hosts:"
        echo "  ${EXISTING_LINE}"
        if [[ $EUID -ne 0 ]]; then
            echo ""
            echo "Root privileges required to update /etc/hosts."
            echo "Run with sudo:"
            echo "  sudo ./ctl hosts"
            echo ""
            echo "Or manually replace the entry in /etc/hosts with:"
            echo "  ${HOSTS_LINE}"
            exit 1
        fi
        sed -i '/airflow\.local/d' /etc/hosts
    fi
fi

if [[ $EUID -ne 0 ]]; then
    echo "Root privileges required to update /etc/hosts."
    echo "Run with sudo:"
    echo "  sudo ./ctl hosts"
    echo ""
    echo "Or manually execute:"
    echo "  echo \"${HOSTS_LINE}\" | sudo tee -a /etc/hosts"
    exit 1
fi

echo "${HOSTS_LINE}" >> /etc/hosts
echo "Successfully updated DNS mappings in /etc/hosts:"
echo "  ${HOSTS_LINE}"
