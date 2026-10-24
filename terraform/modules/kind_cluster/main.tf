resource "kind_cluster" "this" {
  name            = var.cluster_name
  wait_for_ready  = true
  kubeconfig_path = pathexpand("~/.kube/config")

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
      ]

      # Ingress HTTP
      extra_port_mappings {
        container_port = 80
        host_port      = 80
        protocol       = "TCP"
      }

      # Ingress HTTPS (TLS)
      extra_port_mappings {
        container_port = 443
        host_port      = 443
        protocol       = "TCP"
      }

      # Airflow Web UI NodePort 30080 -> Host 8080 (fallback)
      extra_port_mappings {
        container_port = 30080
        host_port      = 8080
        protocol       = "TCP"
      }

      # Celery Flower UI NodePort 30555 -> Host 5555 (fallback)
      extra_port_mappings {
        container_port = 30555
        host_port      = 5555
        protocol       = "TCP"
      }
    }
  }
}
