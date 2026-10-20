#!/usr/bin/env bash
# ==============================================================================
# Airflow Lab Control CLI
# Portable management CLI for local Kubernetes Airflow + Keycloak
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="airflow"

# Color helpers
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

usage() {
    echo -e "${CYAN}Airflow Lab Control CLI${NC}"
    echo "Usage: ./ctl <command>"
    echo ""
    echo "Commands:"
    echo "  status         Show pod health, endpoints, and credentials"
    echo "  start          Provision KinD cluster and deploy Keycloak + Airflow"
    echo "  stop           Tear down the local KinD cluster cleanly"
    echo "  build          Build the custom Airflow 3 Docker image"
    echo "  test-alert     Trigger the failure DAG to verify Gmail failure alerts"
    echo "  test-auth      Verify Keycloak OIDC token issuance and user claims"
    echo "  logs [pod]     Tail logs for worker, scheduler, or keycloak (default: worker)"
    echo "  help           Display this help screen"
}

cmd="${1:-help}"

case "${cmd}" in
    status)
        echo -e "${CYAN}=== Airflow Kubernetes Cluster Status ===${NC}"
        kubectl get pods -n "${NAMESPACE}"
        echo ""
        echo -e "${GREEN}=== Access Endpoints ===${NC}"
        echo -e "Airflow Web UI:  ${YELLOW}http://localhost:8080${NC} (Click 'Sign in with keycloak')"
        echo -e "Keycloak Admin:  ${YELLOW}http://localhost:8081${NC} (User: admin | Pass: admin | Realm: airflow)"
        echo -e "Break-glass:     User: breakglass | Pass: ChangeMeInSecret123!"
        echo ""
        echo -e "${GREEN}=== Keycloak AD Group Users (Owner-Based RBAC) ===${NC}"
        echo "  alice          (Admin)              -> Pass: Alice-lab-1"
        echo "  user_finance   (aid-finance-auth)   -> Pass: Finance-lab-1   (Owns: finance_monthly_report)"
        echo "  user_marketing (aid-marketing-auth) -> Pass: Marketing-lab-1 (Owns: marketing_campaign_tracker)"
        echo "  user_logistics (aid-logistics-auth) -> Pass: Logistics-lab-1 (Owns: logistics_fleet_monitoring)"
        echo "  user_analytics (aid-analytics-auth) -> Pass: Analytics-lab-1 (Owns: analytics_daily_etl)"
        ;;

    start)
        "${ROOT_DIR}/scripts/start-local-k8s.sh"
        ;;

    stop)
        "${ROOT_DIR}/scripts/stop-local-k8s.sh"
        ;;

    build)
        echo -e "${CYAN}Building learn-airflow:3.3.2-python3.12...${NC}"
        docker build -t learn-airflow:3.3.2-python3.12 "${ROOT_DIR}"
        ;;

    test-alert)
        echo -e "${CYAN}Triggering failure drill DAG (team_a_notify_on_failure)...${NC}"
        kubectl exec -n "${NAMESPACE}" deploy/airflow-scheduler -c scheduler -- airflow dags unpause team_a_notify_on_failure 2>/dev/null || true
        kubectl exec -n "${NAMESPACE}" deploy/airflow-scheduler -c scheduler -- airflow dags trigger team_a_notify_on_failure
        echo -e "${YELLOW}Waiting for task execution and Gmail SMTP dispatch...${NC}"
        sleep 6
        kubectl logs -n "${NAMESPACE}" airflow-worker-0 -c worker --tail=30
        ;;

    test-auth)
        echo -e "${CYAN}Testing Keycloak OIDC authentication for all 4 team AD groups...${NC}"
        python3 -c '
import urllib.request, urllib.parse, json

creds = [
    ("user_finance", "Finance-lab-1", "aid-finance-auth"),
    ("user_marketing", "Marketing-lab-1", "aid-marketing-auth"),
    ("user_logistics", "Logistics-lab-1", "aid-logistics-auth"),
    ("user_analytics", "Analytics-lab-1", "aid-analytics-auth"),
]

for username, password, expected_group in creds:
    data = urllib.parse.urlencode({
        "client_id": "airflow",
        "client_secret": "airflow-client-secret",
        "grant_type": "password",
        "username": username,
        "password": password,
        "scope": "openid email profile"
    }).encode()
    req = urllib.request.Request("http://localhost:8081/realms/airflow/protocol/openid-connect/token", data=data)
    token = json.loads(urllib.request.urlopen(req).read().decode())["access_token"]
    req2 = urllib.request.Request("http://localhost:8081/realms/airflow/protocol/openid-connect/userinfo", headers={"Authorization": "Bearer " + token})
    info = json.loads(urllib.request.urlopen(req2).read().decode())
    groups = info.get("groups", [])
    status = "OK" if expected_group in groups else "FAILED"
    print(f"[{status}] {username:16} -> Groups: {groups}")
'
        ;;

    logs)
        target="${2:-worker}"
        case "${target}" in
            worker)
                kubectl logs -n "${NAMESPACE}" airflow-worker-0 -c worker -f
                ;;
            scheduler)
                kubectl logs -n "${NAMESPACE}" deploy/airflow-scheduler -c scheduler -f
                ;;
            keycloak)
                kubectl logs -n "${NAMESPACE}" deploy/keycloak -c keycloak -f
                ;;
            *)
                echo -e "${RED}Unknown logs target: ${target}. Choose: worker, scheduler, keycloak${NC}"
                exit 1
                ;;
        esac
        ;;

    help|--help|-h)
        usage
        ;;

    *)
        echo -e "${RED}Unknown command: ${cmd}${NC}"
        usage
        exit 1
        ;;
esac
