#!/usr/bin/env bash
# ==============================================================================
# Helper to configure /etc/hosts for Airflow Lab TLS Ingress
# Maps internal .local hostnames to the KinD control-plane IP.
# ==============================================================================
set -euo pipefail

CLUSTER_NAME="airflow-local"
NODE_IP=$(docker inspect "${CLUSTER_NAME}-control-plane" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "172.18.0.2")

HOSTS_LINE="${NODE_IP} airflow.local auth.local flower.local grafana.local prometheus.local vault.local minio.local ldap.local artifactory.local"

if grep -q "airflow.local" /etc/hosts; then
    echo "Entry for 'airflow.local' already exists in /etc/hosts:"
    grep "airflow.local" /etc/hosts
    exit 0
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
echo "Successfully added DNS mappings to /etc/hosts:"
echo "  ${HOSTS_LINE}"
