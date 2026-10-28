resource "null_resource" "airflow" {
  triggers = {
    revision = var.source_revision
  }
  provisioner "local-exec" {
    command     = "bash scripts/deploy-airflow.sh && bash scripts/setup-observability.sh"
    working_dir = var.project_root
  }
}
