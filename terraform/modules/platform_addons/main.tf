# 1. cert-manager for automated TLS certificates
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  timeout          = 300

  set {
    name  = "crds.enabled"
    value = "true"
  }
}

# 2. NGINX Ingress Controller for KinD
resource "null_resource" "ingress_nginx" {
  provisioner "local-exec" {
    command = <<-EOT
      kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
      kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=180s 2>/dev/null || true
    EOT
  }
}

# 3. Apply cert-manager ClusterIssuer & Ingress Rules
resource "null_resource" "ingress_rules" {
  depends_on = [helm_release.cert_manager, null_resource.ingress_nginx]

  provisioner "local-exec" {
    command = <<-EOT
      kubectl apply -f ${var.project_root}/k8s/ingress/cluster-issuer.yaml
      kubectl apply -f ${var.project_root}/k8s/ingress/airflow-ingress.yaml
    EOT
  }
}

# 4. KEDA Operator for Celery Worker Autoscaling
resource "helm_release" "keda" {
  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  namespace  = var.keda_namespace
  timeout    = 300
}

# 5. KEDA ScaledObject & TriggerAuthentication
resource "null_resource" "keda_scaledobject" {
  depends_on = [helm_release.keda]

  provisioner "local-exec" {
    command = "kubectl apply -f ${var.project_root}/k8s/keda/keda-scaledobject.yaml"
  }
}

# 6. Observability Stack (Prometheus & Grafana)
resource "null_resource" "observability" {
  provisioner "local-exec" {
    command = <<-EOT
      kubectl apply -f ${var.project_root}/k8s/observability/prometheus.yaml
      kubectl apply -f ${var.project_root}/k8s/observability/grafana.yaml
    EOT
  }
}
