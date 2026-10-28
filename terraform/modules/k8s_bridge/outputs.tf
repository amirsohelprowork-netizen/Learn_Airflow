output "airflow_namespace" {
  value      = "airflow"
  depends_on = [null_resource.bridge]
}
