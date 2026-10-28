resource "null_resource" "addons" {
  triggers = {
    ingress = filesha256("${var.project_root}/scripts/setup-ingress.sh")
    keda    = filesha256("${var.project_root}/scripts/setup-keda.sh")
    routes  = filesha256("${var.project_root}/k8s/ingress/airflow-ingress.yaml")
  }
  provisioner "local-exec" {
    command     = "bash scripts/setup-ingress.sh && bash scripts/setup-keda.sh"
    working_dir = var.project_root
  }
}
