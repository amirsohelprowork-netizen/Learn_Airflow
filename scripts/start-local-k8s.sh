#!/usr/bin/env bash
# Quickstart script to run Apache Airflow locally on KinD (Kubernetes in Docker)
set -euo pipefail

CLUSTER_NAME="airflow-local"
NAMESPACE="airflow"
IMAGE_TAG="learn-airflow:3.3.2-python3.12"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== 1. Checking KinD Cluster ==="
if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
    echo "Creating KinD cluster '${CLUSTER_NAME}' with port mappings (8080 -> 30080)..."
    kind create cluster --config "${ROOT_DIR}/k8s/kind-cluster.yaml"
else
    echo "KinD cluster '${CLUSTER_NAME}' is already running."
fi

echo "=== 2. Building & Loading Docker Image into KinD ==="
echo "Building ${IMAGE_TAG} with authlib..."
docker build -t "${IMAGE_TAG}" "${ROOT_DIR}"
echo "Loading ${IMAGE_TAG} into ${CLUSTER_NAME}..."
kind load docker-image "${IMAGE_TAG}" --name "${CLUSTER_NAME}"

echo "=== 3. Setting Up Namespace & Keycloak ==="
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap keycloak-realm \
    --from-file=airflow-realm.json="${ROOT_DIR}/k8s/keycloak/realm-airflow.json" \
    -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap custom-webserver-config \
    --from-file=webserver_config.py="${ROOT_DIR}/config/webserver_config.py" \
    -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap airflow-webserver-config \
    --from-file=webserver_config.py="${ROOT_DIR}/config/webserver_config.py" \
    -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${ROOT_DIR}/k8s/keycloak/deployment.yaml"

echo "Waiting for Keycloak to be ready..."
kubectl rollout status deployment/keycloak -n "${NAMESPACE}" --timeout=300s

echo "=== 3b. Starting & Mapping External HashiCorp Vault ==="
"${ROOT_DIR}/scripts/setup-vault.sh"


echo "=== 4. Checking Gmail SMTP Secret ==="
if ! kubectl get secret airflow-smtp-secret -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "----------------------------------------------------------------------"
    echo "NOTICE: Secret 'airflow-smtp-secret' not found in namespace '${NAMESPACE}'."
    echo "To send failure emails from alerts@example.com, a 16-char Google App Password is required."
    echo ""
    GMAIL_PASS="${GMAIL_APP_PASSWORD:-}"
    if [[ -z "${GMAIL_PASS}" ]]; then
        if [[ -t 0 ]]; then
            echo "If you have your App Password now, enter it below (or press Enter to create a placeholder):"
            read -r -s -p "Gmail 16-char App Password: " GMAIL_PASS
            echo ""
        fi
    fi
    if [[ -z "${GMAIL_PASS}" ]]; then
        GMAIL_PASS="REPLACE_WITH_YOUR_16_CHAR_GMAIL_APP_PASSWORD"
        echo "Created placeholder secret. Update it with your real password using:"
        echo "  kubectl create secret generic airflow-smtp-secret --from-literal=password=\"<APP_PWD>\" -n ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -"
    fi
    kubectl create secret generic airflow-smtp-secret \
        --from-literal=password="${GMAIL_PASS}" \
        -n "${NAMESPACE}"
else
    echo "Secret 'airflow-smtp-secret' already exists."
fi

echo "=== 4b. Checking Git-Sync SSH Secret ==="
if ! kubectl get secret airflow-ssh-secret -n "${NAMESPACE}" >/dev/null 2>&1; then
    SSH_KEY_FILE="${HOME}/.ssh/id_ed25519"
    if [[ ! -f "${SSH_KEY_FILE}" ]]; then
        SSH_KEY_FILE="${HOME}/.ssh/id_rsa"
    fi
    if [[ -f "${SSH_KEY_FILE}" ]]; then
        kubectl create secret generic airflow-ssh-secret \
            --from-file=gitSshKey="${SSH_KEY_FILE}" \
            -n "${NAMESPACE}"
        echo "Created 'airflow-ssh-secret' from ${SSH_KEY_FILE}."
    else
        echo "WARNING: No SSH key found at ~/.ssh/id_ed25519 or ~/.ssh/id_rsa for git-sync."
    fi
else
    echo "Secret 'airflow-ssh-secret' already exists."
fi

echo "=== 5. Deploying Airflow with Helm ==="
helm repo add apache-airflow https://airflow.apache.org 2>/dev/null || true
helm repo update apache-airflow

helm upgrade --install airflow apache-airflow/airflow \
    -f "${ROOT_DIR}/values.yaml" \
    --namespace "${NAMESPACE}"

echo "Waiting for scheduler pod..."
kubectl rollout status deployment/airflow-scheduler -n "${NAMESPACE}" --timeout=300s

echo "Ensuring AD team roles exist in Airflow database..."
kubectl exec -n "${NAMESPACE}" deploy/airflow-scheduler -c scheduler -- airflow roles create aid-finance-auth 2>/dev/null || true
kubectl exec -n "${NAMESPACE}" deploy/airflow-scheduler -c scheduler -- airflow roles create aid-marketing-auth 2>/dev/null || true
kubectl exec -n "${NAMESPACE}" deploy/airflow-scheduler -c scheduler -- airflow roles create aid-logistics-auth 2>/dev/null || true
kubectl exec -n "${NAMESPACE}" deploy/airflow-scheduler -c scheduler -- airflow roles create aid-analytics-auth 2>/dev/null || true

echo "Seeding base operational permissions for AD team roles..."
kubectl exec -n "${NAMESPACE}" deploy/airflow-scheduler -c scheduler -- python3 -c '
from airflow.providers.fab.auth_manager.models import Role, Permission, Action, Resource
from airflow.settings import Session

session = Session()
roles = ["aid-finance-auth", "aid-marketing-auth", "aid-logistics-auth", "aid-analytics-auth"]
base_perms = [
    ("can_read", "Asset Aliases"), ("can_read", "Assets"), ("menu_access", "Assets"),
    ("can_read", "Backfills"), ("menu_access", "Browse"), ("can_read", "Cluster Activity"),
    ("menu_access", "Cluster Activity"), ("can_read", "DAG Code"), ("can_read", "DAG Dependencies"),
    ("menu_access", "DAG Dependencies"), ("can_read", "DAG Runs"), ("can_create", "DAG Runs"),
    ("can_edit", "DAG Runs"), ("can_delete", "DAG Runs"), ("menu_access", "DAG Runs"),
    ("can_read", "DAG Versions"), ("can_read", "DAG Warnings"), ("menu_access", "DAGs"),
    ("menu_access", "Docs"), ("menu_access", "Documentation"), ("can_read", "HITL Detail"),
    ("can_edit", "HITL Detail"), ("can_read", "ImportError"), ("can_read", "All Import Errors"),
    ("can_read", "Jobs"), ("menu_access", "Jobs"), ("can_edit", "My Password"),
    ("can_read", "My Password"), ("can_edit", "My Profile"), ("can_read", "My Profile"),
    ("can_read", "Pools"), ("can_read", "Plugins"), ("can_read", "SLA Misses"),
    ("menu_access", "SLA Misses"), ("can_read", "Task Instances"), ("can_create", "Task Instances"),
    ("can_edit", "Task Instances"), ("can_delete", "Task Instances"), ("menu_access", "Task Instances"),
    ("can_read", "Task Logs"), ("can_read", "Website"), ("can_read", "XComs"),
]
for r_name in roles:
    r = session.query(Role).filter(Role.name == r_name).first()
    if r:
        for a_name, res_name in base_perms:
            p = session.query(Permission).join(Action).join(Resource).filter(Action.name == a_name, Resource.name == res_name).first()
            if p and p not in r.permissions:
                r.permissions.append(p)
session.commit()
' 2>/dev/null || true


echo ""
echo "======================================================================"
echo "Airflow & Keycloak are deploying to local Kubernetes (KinD)!"
echo "======================================================================"
echo "Airflow Web UI:  http://localhost:8080"
echo "Keycloak Admin:  http://localhost:8081  (User: admin | Pass: admin)"
echo "HashiCorp Vault: http://localhost:8200  (Token: airflow-vault-root-token-2026)"
echo ""
echo "Airflow Logins via Keycloak SSO (Owner-Based RBAC):"
echo "  Alice (Admin)          -> User: alice          | Pass: Alice-lab-1"
echo "  Finance Owner          -> User: user_finance   | Pass: Finance-lab-1"
echo "  Marketing Owner        -> User: user_marketing | Pass: Marketing-lab-1"
echo "  Logistics Owner        -> User: user_logistics | Pass: Logistics-lab-1"
echo "  Analytics Owner        -> User: user_analytics | Pass: Analytics-lab-1"
echo ""
echo "Break-glass Admin: User: breakglass | Pass: ChangeMeInSecret123!"
echo ""
echo "Watch pod status:"
echo "  kubectl get pods -n ${NAMESPACE} -w"
echo ""
echo "Trigger Gmail Failure Notification drill:"
echo "  kubectl exec -it -n ${NAMESPACE} deployment/airflow-scheduler -c scheduler -- airflow dags unpause team_a_notify_on_failure"
echo "  kubectl exec -it -n ${NAMESPACE} deployment/airflow-scheduler -c scheduler -- airflow dags trigger team_a_notify_on_failure"
echo "======================================================================"

