output "cert_manager_status" {
  description = "Status of cert-manager release"
  value       = helm_release.cert_manager.status
}

output "keda_status" {
  description = "Status of KEDA release"
  value       = helm_release.keda.status
}
