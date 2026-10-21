# ==============================================================================
# Airflow 3 + Keycloak Local Kubernetes Development Makefile
# ==============================================================================

.PHONY: help start stop status build test-alert test-auth logs-worker logs-scheduler logs-keycloak

# Default target
help: ## Show this help menu
	@echo "Usage: make [target]"
	@echo ""
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

start: ## Build image, provision KinD cluster, deploy Keycloak & Airflow
	@./scripts/start-local-k8s.sh

stop: ## Tear down the local KinD cluster cleanly
	@./scripts/stop-local-k8s.sh

status: ## Show cluster health, pod status, and access URLs
	@echo "=== Airflow Kubernetes Cluster Status ==="
	@kubectl get pods -n airflow
	@echo ""
	@echo "=== Access Endpoints ==="
	@echo "Airflow Web UI:  http://localhost:8080 (Login with Keycloak SSO)"
	@echo "Keycloak Admin:  http://localhost:8081 (admin / admin | realm: airflow)"
	@echo "Break-glass:     User: breakglass | Pass: ChangeMeInSecret123!"

build: ## Build the custom Airflow 3 Docker image
	@docker build -t learn-airflow:3.3.2-python3.12 .

test-alert: ## Trigger Airflow task failure alert email test to Gmail
	@./ctl test-alert

test-grafana-alert: ## Trigger Grafana Alerting notification test to Gmail
	@./ctl test-grafana-alert


test-auth: ## Test Keycloak token issuance and userinfo claims for all 4 team AD users
	@./ctl test-auth

logs-worker: ## Follow logs for the Airflow Celery worker
	@kubectl logs -n airflow airflow-worker-0 -c worker -f

logs-scheduler: ## Follow logs for the Airflow scheduler
	@kubectl logs -n airflow deploy/airflow-scheduler -c scheduler -f

logs-keycloak: ## Follow logs for Keycloak
	@kubectl logs -n airflow deploy/keycloak -c keycloak -f
