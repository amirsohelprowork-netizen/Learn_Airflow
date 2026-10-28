output "release_name" {
  value      = "airflow"
  depends_on = [null_resource.airflow]
}
