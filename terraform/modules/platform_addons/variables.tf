variable "project_root" {
  type        = string
  description = "Path to repository root"
}

variable "airflow_namespace" {
  type        = string
  description = "Airflow namespace"
  default     = "airflow"
}

variable "observability_namespace" {
  type        = string
  description = "Observability namespace"
  default     = "observability"
}

variable "keda_namespace" {
  type        = string
  description = "KEDA namespace"
  default     = "keda"
}
