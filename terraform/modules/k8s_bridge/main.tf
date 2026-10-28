resource "null_resource" "bridge" {
  triggers = {
    revision = var.source_revision
  }
  provisioner "local-exec" {
    command     = "bash scripts/reconcile-cluster.sh"
    working_dir = var.project_root
  }
}
