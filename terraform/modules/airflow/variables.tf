variable "project_root" {
  type        = string
  description = "Path to repository root"
}

variable "airflow_namespace" {
  type        = string
  description = "Airflow namespace"
  default     = "airflow"
}

variable "cluster_name" {
  type        = string
  description = "KinD cluster name"
  default     = "airflow-local"
}

variable "image_tag" {
  type        = string
  description = "Custom Airflow Docker image tag"
  default     = "learn-airflow:3.3.2-python3.12"
}

variable "breakglass_password" {
  type        = string
  description = "Initial administrator password for break-glass emergency Airflow access"
  default     = "ChangeMeInSecret123!"
  sensitive   = true
}
