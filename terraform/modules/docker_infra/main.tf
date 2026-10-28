# Shared lifecycle script avoids two conflicting definitions of local services.
# Named volumes are deliberately retained on Terraform destroy.
resource "null_resource" "local_services" {
  depends_on = [null_resource.lifecycle]
  triggers = {
    project_root = var.project_root
    revision     = var.source_revision
  }
  provisioner "local-exec" {
    command     = "bash scripts/setup-infra.sh"
    working_dir = self.triggers.project_root
  }
}

resource "null_resource" "lifecycle" {
  triggers = {
    project_root = var.project_root
  }
  provisioner "local-exec" {
    when        = destroy
    command     = "bash scripts/stop-infra.sh"
    working_dir = self.triggers.project_root
  }
}
