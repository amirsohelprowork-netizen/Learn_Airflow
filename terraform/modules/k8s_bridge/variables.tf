variable "airflow_namespace" {
  type        = string
  description = "Kubernetes namespace for Airflow components"
  default     = "airflow"
}

variable "observability_namespace" {
  type        = string
  description = "Kubernetes namespace for Observability components"
  default     = "observability"
}

variable "keda_namespace" {
  type        = string
  description = "Kubernetes namespace for KEDA autoscaler"
  default     = "keda"
}

variable "host_gateway_ip" {
  type        = string
  description = "Gateway IP address of the Docker kind bridge network (172.18.0.1)"
  default     = "172.18.0.1"
}

variable "project_root" {
  type        = string
  description = "Root path to repository"
}

variable "breakglass_password" {
  type        = string
  description = "Password for emergency break-glass admin"
  default     = "ChangeMeInSecret123!"
  sensitive   = true
}

variable "gmail_app_password" {
  type        = string
  description = "Optional Gmail 16-char App Password"
  default     = ""
  sensitive   = true
}

variable "alert_email" {
  type        = string
  description = "Alert email address"
  default     = "alerts@example.com"
}
