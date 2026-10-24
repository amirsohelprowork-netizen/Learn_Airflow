output "cluster_name" {
  description = "Name of the KinD cluster"
  value       = kind_cluster.this.name
}

output "endpoint" {
  description = "Kubernetes API Server endpoint"
  value       = kind_cluster.this.endpoint
}

output "client_certificate" {
  description = "Client certificate for Kubernetes authentication"
  value       = kind_cluster.this.client_certificate
  sensitive   = true
}

output "client_key" {
  description = "Client key for Kubernetes authentication"
  value       = kind_cluster.this.client_key
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Root CA certificate of the KinD cluster"
  value       = kind_cluster.this.cluster_ca_certificate
  sensitive   = true
}

output "kubeconfig_path" {
  description = "Path to the written kubeconfig file"
  value       = kind_cluster.this.kubeconfig_path
}
