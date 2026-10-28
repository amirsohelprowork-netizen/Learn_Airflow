#!/usr/bin/env bash
# Supported local control plane. Kubernetes commands always target the local context.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBE=(kubectl --context kind-airflow-local)
cmd="${1:-help}"
case "$cmd" in
    init) python3 "${ROOT_DIR}/scripts/local_config.py" init ;;
    credentials) python3 "${ROOT_DIR}/scripts/local_config.py" credentials ;;
    start) "${ROOT_DIR}/scripts/start-local-k8s.sh" ;;
    stop) "${ROOT_DIR}/scripts/stop-local-k8s.sh" ;;
    build) "${ROOT_DIR}/scripts/build-image.sh" ;;
    test) "${ROOT_DIR}/scripts/test.sh" "${@:2}" ;;
    ci) "${ROOT_DIR}/scripts/check.sh" ;;
    scan) "${ROOT_DIR}/scripts/scan.sh" "${@:2}" ;;
    smoke) python3 "${ROOT_DIR}/scripts/smoke_test.py" "${@:2}" ;;
    test-auth) python3 "${ROOT_DIR}/scripts/test_oidc.py" ;;
    status)
        "${KUBE[@]}" get pods -n airflow
        "${KUBE[@]}" get pods -n observability
        docker ps --filter 'name=^/airflow-local-' --format 'table {{.Names}}\t{{.Status}}'
        echo 'Airflow: https://localhost | Keycloak: https://localhost:8443 | Inbox: http://localhost:8025'
        echo 'Credentials are private: ./ctl credentials'
        ;;
    autoscaler|keda) "${KUBE[@]}" get scaledobject,hpa -n airflow ;;
    metrics|grafana) "${KUBE[@]}" get pods -n observability; echo 'Use ./ctl ui grafana or ./ctl ui prometheus' ;;
    ui)
        case "${2:-grafana}" in
            grafana) "${KUBE[@]}" port-forward --address 127.0.0.1 -n observability svc/grafana 3000:3000 ;;
            prometheus) "${KUBE[@]}" port-forward --address 127.0.0.1 -n observability svc/prometheus 9090:9090 ;;
            *) echo 'Usage: ./ctl ui grafana|prometheus' >&2; exit 1 ;;
        esac
        ;;
    ingress|tls) "${KUBE[@]}" get ingress -n airflow; echo 'Local CA: .local/tls/ca.crt; Airflow: https://localhost' ;;
    hosts) "${ROOT_DIR}/scripts/setup-hosts.sh" ;;
    test-alert)
        "${KUBE[@]}" exec -n airflow deploy/airflow-scheduler -c scheduler -- airflow dags unpause failure_drill
        "${KUBE[@]}" exec -n airflow deploy/airflow-scheduler -c scheduler -- airflow dags trigger failure_drill
        echo 'Inspect delivery in the local inbox: http://localhost:8025'
        ;;
    test-grafana-alert)
        echo 'Open ./ctl ui grafana, then Alerting > Contact points > email-admin > Test.'
        echo 'Delivery stays on this machine: http://localhost:8025'
        ;;
    logs)
        case "${2:-worker}" in
            worker|scheduler|dag-processor|api-server|triggerer)
                "${KUBE[@]}" logs -n airflow -l "component=${2:-worker}" --all-containers=true --prefix=true -f ;;
            keycloak|vault|postgres|redis) docker logs -f "airflow-local-${2}" ;;
            *) echo 'Unknown log target' >&2; exit 1 ;;
        esac
        ;;
    vault)
        case "${2:-status}" in
            start|seed) "${ROOT_DIR}/scripts/setup-vault.sh" ;;
            status) curl --fail --cacert "${ROOT_DIR}/.local/tls/ca.crt" https://localhost:8200/v1/sys/health ;;
            ui) echo 'https://localhost:8200; bootstrap token is in .local/vault-init.json (never used by Airflow)' ;;
            *) exit 1 ;;
        esac
        ;;
    ldap)
        source "${ROOT_DIR}/scripts/common.sh"
        case "${2:-status}" in
            start) "${ROOT_DIR}/scripts/setup-ldap.sh" ;;
            status) docker ps --filter name=airflow-local-openldap ;;
            ui) echo 'http://localhost:8082; bind DN cn=admin,dc=example,dc=org; use ./ctl credentials' ;;
            list-users|list-groups)
                base=users; [[ "$2" == list-groups ]] && base=groups
                docker exec airflow-local-openldap ldapsearch -x -H ldap://localhost \
                    -D cn=admin,dc=example,dc=org -w "${LDAP_ADMIN_PASSWORD}" \
                    -b "ou=${base},dc=example,dc=org" '(objectClass=*)' uid cn member
                ;;
            *) echo 'Usage: ./ctl ldap start|status|ui|list-users|list-groups' >&2; exit 1 ;;
        esac
        ;;
    artifactory)
        case "${2:-status}" in
            start) "${ROOT_DIR}/scripts/setup-artifactory.sh" ;;
            status) docker ps --filter name=airflow-local-artifactory ;;
            ui) echo 'http://localhost:8085; use ./ctl credentials' ;;
            *) exit 1 ;;
        esac
        ;;
    terraform)
        python3 "${ROOT_DIR}/scripts/local_config.py" init
        action="${2:-plan}"
        case "$action" in init|plan|apply|destroy|validate|output|fmt) ;; *) echo 'Unsupported Terraform action' >&2; exit 1 ;; esac
        terraform -chdir="${ROOT_DIR}/terraform" "$action" "${@:3}"
        ;;
    hooks)
        case "${2:-install}" in
            install) git -C "${ROOT_DIR}" config core.hooksPath .githooks ;;
            uninstall) git -C "${ROOT_DIR}" config --unset core.hooksPath ;;
            status) git -C "${ROOT_DIR}" config --get core.hooksPath ;;
            *) exit 1 ;;
        esac
        ;;
    bundle) python3 "${ROOT_DIR}/scripts/copy_repo_to_txt.py" "${@:2}" ;;
    help|--help|-h)
        cat <<'EOF'
Usage: ./ctl <command>
  init          Generate persistent local secrets and TLS certificates
  start / stop  Start or stop local services; preserve data and credentials
  build         Build an image tagged from all its source inputs
  test          Run tests in the actual Airflow image (--static for host-only tests)
  ci            Validate code, Terraform, Helm rendering, and the runtime image
  scan [image]  Fail on fixable high/critical image vulnerabilities
  smoke         Verify a running installation (--run-dag for a finance workflow)
  credentials   Explicitly display local generated credentials
  status        Show local cluster and service health
  ui <service>  Forward grafana or prometheus to a loopback port
  autoscaler    Show KEDA and worker scaling status
  test-alert    Trigger a failure email into the local Mailpit inbox
  logs <target> Follow worker, scheduler, dag-processor, api-server, or service logs
  terraform     Run init, plan, apply, destroy, validate, output or fmt
  ldap / vault / artifactory / ingress / metrics / hooks / bundle
See docs/LOCAL_SETUP.md for prerequisites, trust setup, and local limitations.
EOF
        ;;
    *) echo "Unknown command: $cmd" >&2; exit 1 ;;
esac
