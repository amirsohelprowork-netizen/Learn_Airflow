variable "cluster_name" {
  type        = string
  description = "Name of the local KinD cluster"
  default     = "airflow-local"
}

variable "airflow_namespace" {
  type        = string
  description = "Kubernetes namespace for Apache Airflow components"
  default     = "airflow"
}

variable "observability_namespace" {
  type        = string
  description = "Kubernetes namespace for Prometheus & Grafana"
  default     = "observability"
}

variable "keda_namespace" {
  type        = string
  description = "Kubernetes namespace for KEDA autoscaler"
  default     = "keda"
}

variable "host_gateway_ip" {
  type        = string
  description = "Docker bridge gateway IP through which pods reach external host containers"
  default     = "172.18.0.1"
}

variable "breakglass_password" {
  type        = string
  description = "Initial administrator password for break-glass emergency Airflow access"
  default     = "ChangeMeInSecret123!"
  sensitive   = true
}

variable "gmail_app_password" {
  type        = string
  description = "Optional 16-character Google App Password for outbound failure alerting drills"
  default     = ""
  sensitive   = true
}

variable "alert_email" {
  type        = string
  description = "Sender and notification recipient email for pipeline failure drills"
  default     = "alerts@example.com"
}

variable "image_tag" {
  type        = string
  description = "Docker image tag for the custom Airflow 3 runtime"
  default     = "learn-airflow:3.3.2-python3.12"
}

variable "deploy_addons" {
  type        = bool
  description = "Whether to deploy Ingress, cert-manager, KEDA, and Observability stack"
  default     = true
}

variable "deploy_airflow_helm" {
  type        = bool
  description = "Whether to deploy the Apache Airflow Helm release"
  default     = true
}
