output "release_name" {
  description = "Name of the Airflow Helm release"
  value       = helm_release.airflow.name
}

output "status" {
  description = "Status of the Airflow Helm deployment"
  value       = helm_release.airflow.status
}
