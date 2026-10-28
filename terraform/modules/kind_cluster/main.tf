resource "kind_cluster" "this" {
  name            = var.cluster_name
  node_image      = "kindest/node:v1.34.0@sha256:7416a61b42b1662ca6ca89f02028ac133a309a2a30ba309614e8ec94d976dc5a"
  wait_for_ready  = true
  kubeconfig_path = pathexpand("~/.kube/config")
  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"
    node {
      role = "control-plane"
      extra_port_mappings {
        container_port = 30080
        host_port      = 80
        listen_address = "127.0.0.1"
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 30443
        host_port      = 443
        listen_address = "127.0.0.1"
        protocol       = "TCP"
      }
    }
  }
}
