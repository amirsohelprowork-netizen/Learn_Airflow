variable "project_root" {
  type        = string
  description = "Absolute or relative path to the repository root directory"
}

variable "network_name" {
  type        = string
  description = "Docker network name to attach external stateful containers to"
  default     = "kind"
}

variable "artifactory_ui_port" {
  type        = number
  description = "Host port for Sonatype Nexus 3 OSS Web UI and REST API"
  default     = 8085
}

variable "artifactory_docker_port" {
  type        = number
  description = "Host port for Nexus Docker registry mirror"
  default     = 5000
}

variable "postgres_port" {
  type        = number
  description = "Host port for PostgreSQL 16 metadata database"
  default     = 5432
}

variable "redis_port" {
  type        = number
  description = "Host port for Redis 7 Celery message broker"
  default     = 6379
}

variable "vault_port" {
  type        = number
  description = "Host port for HashiCorp Vault server"
  default     = 8200
}

variable "minio_port" {
  type        = number
  description = "Host port for MinIO S3 API"
  default     = 9000
}

variable "minio_console_port" {
  type        = number
  description = "Host port for MinIO Console Web UI"
  default     = 9001
}

variable "keycloak_port" {
  type        = number
  description = "Host port for Keycloak 26 OIDC Identity Provider"
  default     = 8081
}

variable "ldap_port" {
  type        = number
  description = "Host port for OpenLDAP directory server"
  default     = 389
}

variable "phpldapadmin_port" {
  type        = number
  description = "Host port for phpLDAPadmin Web GUI"
  default     = 8082
}
