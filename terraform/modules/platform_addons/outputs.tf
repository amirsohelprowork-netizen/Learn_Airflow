output "ready" {
  value      = true
  depends_on = [null_resource.addons]
}
