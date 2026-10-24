# 1. Build Custom Airflow Image via Nexus Artifactory and Load into KinD
resource "null_resource" "build_and_load_image" {
  triggers = {
    dockerfile_hash   = filemd5("${var.project_root}/Dockerfile")
    requirements_hash = filemd5("${var.project_root}/requirements.txt")
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Building ${var.image_tag} via Artifactory PyPI proxy..."
      docker build --network=host -t "${var.image_tag}" "${var.project_root}"
      echo "Loading image into KinD cluster '${var.cluster_name}'..."
      kind load docker-image "${var.image_tag}" --name "${var.cluster_name}"
    EOT
  }
}

# 2. Deploy Apache Airflow 3 Helm Release
resource "helm_release" "airflow" {
  depends_on = [null_resource.build_and_load_image]

  name       = "airflow"
  repository = "http://localhost:8085/repository/helm-proxy/"
  chart      = "airflow"
  namespace  = var.airflow_namespace
  timeout    = 600

  values = [
    file("${var.project_root}/values.yaml")
  ]

  set_sensitive {
    name  = "createUserJob.defaultUser.password"
    value = var.breakglass_password
  }
}

# 3. Post-Deployment: Seed AD Security Group Roles & Operational Permissions
resource "null_resource" "seed_rbac_roles" {
  depends_on = [helm_release.airflow]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for Airflow Scheduler rollout..."
      kubectl rollout status deployment/airflow-scheduler -n "${var.airflow_namespace}" --timeout=300s
      kubectl rollout status deployment/airflow-api-server -n "${var.airflow_namespace}" --timeout=300s

      echo "Ensuring AD team roles exist in Airflow database..."
      for role in aid-finance-auth aid-marketing-auth aid-logistics-auth aid-analytics-auth; do
        kubectl exec -n "${var.airflow_namespace}" deploy/airflow-scheduler -c scheduler -- \
          airflow roles create "$role" 2>/dev/null || true
      done

      echo "Seeding base operational permissions for Airflow 3 modern UI..."
      kubectl exec -n "${var.airflow_namespace}" deploy/airflow-scheduler -c scheduler -- python3 -c '
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
    ("can_edit", "HITL Detail"), ("can_read", "ImportError"),
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

      echo "Seeding department execution pools..."
      for dept in finance marketing logistics analytics; do
        kubectl exec -n "${var.airflow_namespace}" deploy/airflow-scheduler -c scheduler -- \
          airflow pools set "$${dept}_pool" 8 "$${dept^} department execution pool" 2>/dev/null || true
      done
    EOT
  }
}
