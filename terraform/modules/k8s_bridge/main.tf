# Namespaces
resource "kubernetes_namespace" "airflow" {
  metadata {
    name = var.airflow_namespace
  }
}

resource "kubernetes_namespace" "observability" {
  metadata {
    name = var.observability_namespace
  }
}

resource "kubernetes_namespace" "keda" {
  metadata {
    name = var.keda_namespace
  }
}

# 1. PostgreSQL Service & Endpoints
resource "kubernetes_service" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  spec {
    port {
      name        = "tcp-postgresql"
      port        = 5432
      target_port = 5432
    }
  }
}

resource "kubernetes_endpoints" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  subset {
    address {
      ip = var.host_gateway_ip
    }
    port {
      name = "tcp-postgresql"
      port = 5432
    }
  }
}

# 2. Redis Service & Endpoints
resource "kubernetes_service" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  spec {
    port {
      name        = "redis"
      port        = 6379
      target_port = 6379
    }
  }
}

resource "kubernetes_endpoints" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  subset {
    address {
      ip = var.host_gateway_ip
    }
    port {
      name = "redis"
      port = 6379
    }
  }
}

# 3. Vault Service & Endpoints
resource "kubernetes_service" "vault" {
  metadata {
    name      = "vault"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  spec {
    port {
      name        = "http"
      port        = 8200
      target_port = 8200
    }
  }
}

resource "kubernetes_endpoints" "vault" {
  metadata {
    name      = "vault"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  subset {
    address {
      ip = var.host_gateway_ip
    }
    port {
      name = "http"
      port = 8200
    }
  }
}

# 4. S3 (MinIO) Service & Endpoints
resource "kubernetes_service" "s3" {
  metadata {
    name      = "s3"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  spec {
    port {
      name        = "http"
      port        = 9000
      target_port = 9000
    }
    port {
      name        = "console"
      port        = 9001
      target_port = 9001
    }
  }
}

resource "kubernetes_endpoints" "s3" {
  metadata {
    name      = "s3"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  subset {
    address {
      ip = var.host_gateway_ip
    }
    port {
      name = "http"
      port = 9000
    }
    port {
      name = "console"
      port = 9001
    }
  }
}

# 5. Keycloak Service & Endpoints
resource "kubernetes_service" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  spec {
    port {
      name        = "http"
      port        = 8080
      target_port = 8081
    }
  }
}

resource "kubernetes_endpoints" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  subset {
    address {
      ip = var.host_gateway_ip
    }
    port {
      name = "http"
      port = 8081
    }
  }
}

# 6. OpenLDAP Service & Endpoints
resource "kubernetes_service" "openldap" {
  metadata {
    name      = "openldap"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  spec {
    port {
      name        = "ldap"
      port        = 389
      target_port = 389
    }
  }
}

resource "kubernetes_endpoints" "openldap" {
  metadata {
    name      = "openldap"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  subset {
    address {
      ip = var.host_gateway_ip
    }
    port {
      name = "ldap"
      port = 389
    }
  }
}

# 7. phpLDAPadmin Service & Endpoints
resource "kubernetes_service" "phpldapadmin" {
  metadata {
    name      = "phpldapadmin"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  spec {
    port {
      name        = "http"
      port        = 80
      target_port = 8082
    }
  }
}

resource "kubernetes_endpoints" "phpldapadmin" {
  metadata {
    name      = "phpldapadmin"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  subset {
    address {
      ip = var.host_gateway_ip
    }
    port {
      name = "http"
      port = 8082
    }
  }
}

# 8. Artifactory (Nexus 3) Service & Endpoints
resource "kubernetes_service" "artifactory" {
  metadata {
    name      = "artifactory"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  spec {
    port {
      name        = "http"
      port        = 8085
      target_port = 8085
    }
    port {
      name        = "docker"
      port        = 5000
      target_port = 5000
    }
  }
}

resource "kubernetes_endpoints" "artifactory" {
  metadata {
    name      = "artifactory"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  subset {
    address {
      ip = var.host_gateway_ip
    }
    port {
      name = "http"
      port = 8085
    }
    port {
      name = "docker"
      port = 5000
    }
  }
}

# ConfigMap for Airflow Webserver OIDC Config
resource "kubernetes_config_map" "webserver_config" {
  metadata {
    name      = "airflow-webserver-config"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  data = {
    "webserver_config.py" = file("${var.project_root}/config/webserver_config.py")
  }
}

# Secrets
resource "kubernetes_secret" "breakglass_admin" {
  metadata {
    name      = "airflow-breakglass-secret"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  data = {
    password = var.breakglass_password
  }
}

resource "kubernetes_secret" "airflow_smtp" {
  metadata {
    name      = "airflow-smtp-secret"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  data = {
    password = var.gmail_app_password != "" ? var.gmail_app_password : "REPLACE_WITH_YOUR_16_CHAR_GMAIL_APP_PASSWORD"
  }
}

resource "kubernetes_secret" "grafana_smtp" {
  metadata {
    name      = "grafana-smtp-secret"
    namespace = kubernetes_namespace.observability.metadata[0].name
  }
  data = {
    password = var.gmail_app_password != "" ? var.gmail_app_password : "REPLACE_WITH_YOUR_16_CHAR_GMAIL_APP_PASSWORD"
  }
}

resource "kubernetes_secret" "vault_token" {
  metadata {
    name      = "airflow-vault-token"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  data = {
    token = "airflow-vault-root-token-2026"
  }
}
