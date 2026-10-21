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
    echo "  autoscaler     View KEDA worker autoscaler targets, HPA, and replica counts"
    echo "  metrics        View Prometheus & Grafana status and dashboard URLs"
    echo "  ingress        View Ingress routing, cert-manager TLS certificates, and DNS"
    echo "  hosts          Add or check /etc/hosts DNS mappings for all TLS Ingress services"
    echo "  test-alert     Trigger the failure DAG to verify Gmail failure alerts"
    echo "  test-auth      Verify Keycloak OIDC token issuance and user claims"
    echo "  logs [pod]     Tail logs for worker, scheduler, or keycloak (default: worker)"
    echo "  vault [action] Manage external HashiCorp Vault (status, ui, start, seed)"
    echo "  ldap [action]  Manage Enterprise OpenLDAP (status, ui, add-user, list-users, list-groups, sync)"
    echo "  help           Display this help screen"
}

cmd="${1:-help}"

case "${cmd}" in
    status)
        echo -e "${CYAN}=== Airflow Kubernetes Cluster (Compute Layer: namespace/airflow) ===${NC}"
        kubectl get pods -n "${NAMESPACE}"
        echo ""
        echo -e "${CYAN}=== Observability Stack (Prometheus + Grafana: namespace/observability) ===${NC}"
        kubectl get pods -n observability 2>/dev/null || true
        echo ""
        echo -e "${CYAN}=== Worker Autoscaler (KEDA Operator: namespace/keda) ===${NC}"
        kubectl get pods -n keda 2>/dev/null || true
        echo ""
        echo -e "${CYAN}=== External Infrastructure Services (Data & Security) ===${NC}"
        docker ps --filter "name=^/airflow-(keycloak|openldap|phpldapadmin|postgres|redis|vault|minio)$" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo ""
        NODE_IP=$(docker inspect airflow-local-control-plane --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "172.18.0.2")
        echo -e "${GREEN}=== Secure Enterprise Ingress Endpoints (HTTPS / TLS) ===${NC}"
        echo -e "  Airflow Web UI:  ${CYAN}https://airflow.local${NC}  or  ${YELLOW}https://airflow.${NODE_IP}.nip.io${NC}"
        echo -e "  Keycloak SSO:    ${CYAN}https://auth.local${NC}     or  ${YELLOW}https://auth.${NODE_IP}.nip.io${NC}"
        echo -e "  Flower UI:       ${CYAN}https://flower.local${NC}   or  ${YELLOW}https://flower.${NODE_IP}.nip.io${NC}"
        echo -e "  Grafana UI:      ${CYAN}https://grafana.local${NC}  or  ${YELLOW}https://grafana.${NODE_IP}.nip.io${NC}"
        echo -e "  Prometheus UI:   ${CYAN}https://prometheus.local${NC} or ${YELLOW}https://prometheus.${NODE_IP}.nip.io${NC}"
        echo -e "  HashiCorp Vault: ${CYAN}https://vault.local${NC}    or  ${YELLOW}https://vault.${NODE_IP}.nip.io${NC}"
        echo -e "  MinIO Console:   ${CYAN}https://minio.local${NC}    or  ${YELLOW}https://minio.${NODE_IP}.nip.io${NC}"
        echo -e "  phpLDAPadmin:    ${CYAN}https://ldap.local${NC}     or  ${YELLOW}https://ldap.${NODE_IP}.nip.io${NC}"
        echo ""
        echo -e "${GREEN}=== Direct Port Endpoints (HTTP Fallback) ===${NC}"
        echo -e "  Airflow Web UI:  http://localhost:8080"
        echo -e "  Keycloak Admin:  http://localhost:8081  (User: admin | Pass: admin | Realm: airflow)"
        echo -e "  Flower Monitor:  http://localhost:5555"
        echo -e "  HashiCorp Vault: http://localhost:8200  (Token: airflow-vault-root-token-2026)"
        echo -e "  MinIO Console:   http://localhost:9001  (User: minioadmin | Pass: minioadmin)"
        echo -e "  phpLDAPadmin:    http://localhost:8082  (Login DN: cn=admin,dc=example,dc=org | Pass: admin)"
        echo -e "  OpenLDAP Server: ldap://localhost:389"
        echo ""
        echo -e "${GREEN}=== Enterprise Users & RBAC Matrix (Source: OpenLDAP) ===${NC}"
        echo "  alice          (Admin)              -> Pass: Alice-lab-1     (LDAP Group: airflow-admins)"
        echo "  breakglass     (Admin)              -> Pass: (read from secret 'airflow-breakglass-secret')"
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

    autoscaler|keda)
        echo -e "${CYAN}=== KEDA Worker Autoscaler Status ===${NC}"
        kubectl get scaledobject,hpa -n "${NAMESPACE}"
        echo ""
        echo -e "${CYAN}=== Current Celery Worker Pods ===${NC}"
        kubectl get pods -n "${NAMESPACE}" -l tier=airflow,component=worker
        echo ""
        echo -e "${CYAN}=== Database Task Queue Depth ===${NC}"
        docker exec -i airflow-postgres psql -U airflow -d airflow -c "SELECT state, queue, count(*) FROM task_instance WHERE state IN ('running', 'queued') GROUP BY state, queue;" 2>/dev/null || echo "No active or queued tasks."
        ;;

    metrics|grafana)
        echo -e "${CYAN}=== Observability Stack Status (Prometheus + Grafana) ===${NC}"
        kubectl get pods -n observability
        echo ""
        echo -e "${GREEN}=== Access URLs ===${NC}"
        echo -e "Grafana UI:    ${CYAN}https://grafana.local${NC}  (or http://localhost:3000 via port-forward)"
        echo -e "Prometheus UI: ${CYAN}https://prometheus.local${NC} (or http://localhost:9090 via port-forward)"
        echo ""
        echo -e "${YELLOW}To port-forward Grafana locally on port 3000:${NC}"
        echo "  kubectl port-forward svc/grafana 3000:3000 -n observability"
        echo ""
        echo -e "${YELLOW}To port-forward Prometheus locally on port 9090:${NC}"
        echo "  kubectl port-forward svc/prometheus 9090:9090 -n observability"
        ;;

    ingress|tls)
        echo -e "${CYAN}=== Kubernetes Ingress Resources ===${NC}"
        kubectl get ingress -A
        echo ""
        echo -e "${CYAN}=== cert-manager TLS Certificates & CA Issuers ===${NC}"
        kubectl get clusterissuer
        echo ""
        kubectl get certificate -n "${NAMESPACE}"
        NODE_IP=$(docker inspect airflow-local-control-plane --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "172.18.0.2")
        echo -e "${GREEN}=== Immediate Zero-Config Access (Wildcard DNS) ===${NC}"
        echo "Works instantly in any browser without modifying /etc/hosts:"
        echo -e "  Airflow Web UI:  ${CYAN}https://airflow.${NODE_IP}.nip.io${NC}"
        echo -e "  Keycloak SSO:    ${CYAN}https://auth.${NODE_IP}.nip.io${NC}"
        echo -e "  Flower UI:       ${CYAN}https://flower.${NODE_IP}.nip.io${NC}"
        echo -e "  Grafana UI:      ${CYAN}https://grafana.${NODE_IP}.nip.io${NC}"
        echo -e "  Prometheus UI:   ${CYAN}https://prometheus.${NODE_IP}.nip.io${NC}"
        echo -e "  HashiCorp Vault: ${CYAN}https://vault.${NODE_IP}.nip.io${NC}"
        echo -e "  MinIO Console:   ${CYAN}https://minio.${NODE_IP}.nip.io${NC}"
        echo -e "  phpLDAPadmin:    ${CYAN}https://ldap.${NODE_IP}.nip.io${NC}"
        echo ""
        echo -e "${GREEN}=== Short Domain Access (/etc/hosts) ===${NC}"
        echo "Run './ctl hosts' to configure /etc/hosts for short domains:"
        echo -e "  ${YELLOW}${NODE_IP} airflow.local auth.local flower.local grafana.local prometheus.local vault.local minio.local ldap.local${NC}"
        ;;

    hosts)
        "${ROOT_DIR}/scripts/setup-hosts.sh"
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
    ("alice", "Alice-lab-1", "airflow-admins"),
    ("breakglass", "ChangeMeInSecret123!", "airflow-admins"),
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
                docker logs -f airflow-keycloak
                ;;
            *)
                echo -e "${RED}Unknown logs target: ${target}. Choose: worker, scheduler, keycloak${NC}"
                exit 1
                ;;
        esac
        ;;

    vault)
        action="${2:-status}"
        case "${action}" in
            start|seed)
                "${ROOT_DIR}/scripts/setup-vault.sh"
                ;;
            status)
                echo -e "${CYAN}=== External HashiCorp Vault Status ===${NC}"
                docker ps --filter "name=airflow-vault"
                echo ""
                curl -s http://localhost:8200/v1/sys/health | python3 -m json.tool 2>/dev/null || echo "Vault not reachable"
                ;;
            ui)
                echo -e "${GREEN}HashiCorp Vault Web UI: ${YELLOW}http://localhost:8200${NC}"
                echo -e "Root Token:              ${YELLOW}airflow-vault-root-token-2026${NC}"
                ;;
            *)
                echo -e "${RED}Unknown vault action: ${action}. Use: status, ui, start, seed${NC}"
                exit 1
                ;;
        esac
        ;;

    ldap)
        action="${2:-status}"
        case "${action}" in
            start)
                "${ROOT_DIR}/scripts/setup-ldap.sh"
                ;;
            status)
                echo -e "${CYAN}=== External OpenLDAP & phpLDAPadmin Status ===${NC}"
                docker ps --filter "name=^/airflow-(openldap|phpldapadmin)$" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
                ;;
            ui)
                echo -e "${GREEN}phpLDAPadmin Web GUI: ${YELLOW}http://localhost:8082${NC}"
                echo -e "Login DN:             ${YELLOW}cn=admin,dc=example,dc=org${NC}"
                echo -e "Password:             ${YELLOW}admin${NC}"
                ;;
            list-users)
                echo -e "${CYAN}=== Users in OpenLDAP (ou=users,dc=example,dc=org) ===${NC}"
                docker exec airflow-openldap ldapsearch -x -H ldap://localhost -b "ou=users,dc=example,dc=org" -D "cn=admin,dc=example,dc=org" -w admin "(objectClass=inetOrgPerson)" uid cn mail | grep -E "^(dn|uid|cn|mail):"
                ;;
            list-groups)
                echo -e "${CYAN}=== AD Groups & Members in OpenLDAP (ou=groups,dc=example,dc=org) ===${NC}"
                docker exec airflow-openldap ldapsearch -x -H ldap://localhost -b "ou=groups,dc=example,dc=org" -D "cn=admin,dc=example,dc=org" -w admin "(objectClass=groupOfNames)" cn member | grep -E "^(dn|cn|member):"
                ;;
            add-user)
                new_user="${3:-}"
                new_fname="${4:-}"
                new_lname="${5:-}"
                new_email="${6:-}"
                new_pass="${7:-}"
                target_group="${8:-}"
                if [[ -z "${new_user}" || -z "${new_fname}" || -z "${new_lname}" || -z "${new_email}" || -z "${new_pass}" || -z "${target_group}" ]]; then
                    echo -e "${RED}Usage: ./ctl ldap add-user <username> <firstName> <lastName> <email> <password> <group>${NC}"
                    echo "Example: ./ctl ldap add-user bob Bob Builder bob@example.com Secret123! aid-finance-auth"
                    exit 1
                fi
                echo -e "${CYAN}Creating user '${new_user}' in OpenLDAP...${NC}"
                docker exec -i airflow-openldap ldapadd -x -D "cn=admin,dc=example,dc=org" -w admin << EOF
dn: uid=${new_user},ou=users,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
uid: ${new_user}
cn: ${new_fname} ${new_lname}
sn: ${new_lname}
givenName: ${new_fname}
mail: ${new_email}
userPassword: ${new_pass}
EOF
                echo -e "${CYAN}Adding '${new_user}' to AD group '${target_group}'...${NC}"
                docker exec -i airflow-openldap ldapmodify -x -D "cn=admin,dc=example,dc=org" -w admin << EOF
dn: cn=${target_group},ou=groups,dc=example,dc=org
changetype: modify
add: member
member: uid=${new_user},ou=users,dc=example,dc=org
EOF
                echo -e "${GREEN}User '${new_user}' created in LDAP and joined group '${target_group}'.${NC}"
                echo "Triggering Keycloak sync..."
                "${ROOT_DIR}/ctl" ldap sync
                ;;
            sync)
                echo -e "${CYAN}Triggering Keycloak LDAP User Federation Sync...${NC}"
                TOKEN=$(curl -s -d "client_id=admin-cli" -d "username=admin" -d "password=admin" -d "grant_type=password" http://localhost:8081/realms/master/protocol/openid-connect/token | jq -r .access_token)
                COMP_ID=$(curl -s -H "Authorization: Bearer ${TOKEN}" http://localhost:8081/admin/realms/airflow/components | jq -r '.[] | select(.name=="openldap" and .providerType=="org.keycloak.storage.UserStorageProvider") | .id')
                if [[ -n "${COMP_ID}" && "${COMP_ID}" != "null" ]]; then
                    curl -s -X POST -H "Authorization: Bearer ${TOKEN}" "http://localhost:8081/admin/realms/airflow/user-storage/${COMP_ID}/sync?action=triggerFullSync" | jq .
                else
                    echo -e "${RED}LDAP provider not found in Keycloak realm 'airflow'.${NC}"
                fi
                ;;
            *)
                echo -e "${RED}Unknown ldap action: ${action}. Use: status, ui, start, add-user, list-users, list-groups, sync${NC}"
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
