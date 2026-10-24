output "artifactory_container_name" {
  description = "Name of the Artifactory container"
  value       = docker_container.artifactory.name
}

output "postgres_container_name" {
  description = "Name of the PostgreSQL container"
  value       = docker_container.postgres.name
}

output "redis_container_name" {
  description = "Name of the Redis container"
  value       = docker_container.redis.name
}

output "vault_container_name" {
  description = "Name of the Vault container"
  value       = docker_container.vault.name
}

output "minio_container_name" {
  description = "Name of the MinIO container"
  value       = docker_container.minio.name
}

output "keycloak_container_name" {
  description = "Name of the Keycloak container"
  value       = docker_container.keycloak.name
}

output "openldap_container_name" {
  description = "Name of the OpenLDAP container"
  value       = docker_container.openldap.name
}

output "ready" {
  description = "Flag indicating external Docker infrastructure is provisioned"
  value       = true
  depends_on = [
    null_resource.artifactory_setup,
    null_resource.vault_setup,
    null_resource.minio_buckets
  ]
}
