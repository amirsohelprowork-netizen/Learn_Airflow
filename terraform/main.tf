locals {
  project_root = abspath("${path.root}/..")
}

# 1. External Docker Infrastructure (Nexus Artifactory, Postgres, Redis, Vault, MinIO, LDAP, Keycloak)
module "docker_infra" {
  source       = "./modules/docker_infra"
  project_root = local.project_root
}

# 2. Local KinD Cluster (Kubernetes in Docker with Ingress Port Mappings)
module "kind_cluster" {
  source       = "./modules/kind_cluster"
  cluster_name = var.cluster_name

  depends_on = [module.docker_infra]
}

# 3. Kubernetes Bridge (Namespaces, Headless Services & Endpoints to 172.18.0.1, Secrets, ConfigMaps)
module "k8s_bridge" {
  source = "./modules/k8s_bridge"

  airflow_namespace       = var.airflow_namespace
  observability_namespace = var.observability_namespace
  keda_namespace          = var.keda_namespace
  host_gateway_ip         = var.host_gateway_ip
  project_root            = local.project_root
  breakglass_password     = var.breakglass_password
  gmail_app_password      = var.gmail_app_password
  alert_email             = var.alert_email

  depends_on = [module.kind_cluster]
}

# 4. Platform Add-ons (Ingress NGINX, cert-manager CA/TLS, KEDA Autoscaler, Prometheus & Grafana)
module "platform_addons" {
  count  = var.deploy_addons ? 1 : 0
  source = "./modules/platform_addons"

  project_root            = local.project_root
  airflow_namespace       = var.airflow_namespace
  observability_namespace = var.observability_namespace
  keda_namespace          = var.keda_namespace

  depends_on = [module.k8s_bridge]
}

# 5. Apache Airflow 3 Helm Deployment (Custom Image Build via Artifactory + Helm Chart + RBAC Seeding)
module "airflow" {
  count  = var.deploy_airflow_helm ? 1 : 0
  source = "./modules/airflow"

  project_root        = local.project_root
  airflow_namespace   = var.airflow_namespace
  cluster_name        = var.cluster_name
  image_tag           = var.image_tag
  breakglass_password = var.breakglass_password

  depends_on = [module.platform_addons]
}
