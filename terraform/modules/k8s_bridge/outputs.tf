output "airflow_namespace" {
  description = "Airflow namespace name"
  value       = kubernetes_namespace.airflow.metadata[0].name
}

output "observability_namespace" {
  description = "Observability namespace name"
  value       = kubernetes_namespace.observability.metadata[0].name
}

output "keda_namespace" {
  description = "KEDA namespace name"
  value       = kubernetes_namespace.keda.metadata[0].name
}

output "webserver_config_map_name" {
  description = "Name of the webserver ConfigMap"
  value       = kubernetes_config_map.webserver_config.metadata[0].name
}
