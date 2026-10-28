# ==============================================================================
# Airflow 3 + Keycloak Local Kubernetes Development Makefile
# ==============================================================================

.PHONY: help start stop status build test ci hooks test-alert test-grafana-alert test-auth logs-worker logs-scheduler logs-keycloak tf-init tf-plan tf-apply tf-destroy bundle

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

status: ## Show local cluster health and access URLs
	@./ctl status

build: ## Build the content-addressed local runtime
	@./ctl build

test-alert: ## Trigger Airflow task failure alert email test to the local inbox
	@./ctl test-alert

test-grafana-alert: ## Trigger Grafana Alerting notification test to the local inbox
	@./ctl test-grafana-alert


ci: ## Run complete local CI/CD pipeline and quality gate
	@./ctl ci

hooks: ## Install local Git pre-commit hooks for automated quality gates
	@./ctl hooks install

test: ## Run CI/CD DAG governance and policy validation suite
	@./ctl test

test-auth: ## Test Keycloak token issuance and userinfo claims for all 4 team AD users
	@./ctl test-auth

logs-worker: ## Follow logs for all Airflow Celery workers
	@kubectl logs -n airflow -l tier=airflow,component=worker -c worker -f --prefix=true

logs-scheduler: ## Follow logs for the Airflow scheduler
	@kubectl logs -n airflow deploy/airflow-scheduler -c scheduler -f

logs-keycloak: ## Follow logs for Keycloak
	@./ctl logs keycloak

tf-init: ## Initialize Terraform providers and modules
	@./ctl terraform init

tf-plan: ## Show Terraform execution plan for local infrastructure
	@./ctl terraform plan

tf-apply: ## Provision entire local infrastructure via Terraform
	@./ctl terraform apply

tf-destroy: ## Tear down all local infrastructure via Terraform
	@./ctl terraform destroy

bundle: ## Export entire repository into a single text file (repo_bundle.txt)
	@python3 scripts/copy_repo_to_txt.py
