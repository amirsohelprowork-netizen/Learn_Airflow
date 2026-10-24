output "cluster_name" {
  description = "KinD Cluster Name"
  value       = module.kind_cluster.cluster_name
}

output "kubernetes_endpoint" {
  description = "Kubernetes Control Plane API URL"
  value       = module.kind_cluster.endpoint
}

output "web_consoles" {
  description = "Directory of all secure HTTPS and direct HTTP web consoles"
  value = {
    airflow_web_ui = "https://airflow.local (or http://localhost:8080)"
    keycloak_sso   = "https://auth.local (or http://localhost:8081)"
    flower_ui      = "https://flower.local (or http://localhost:5555)"
    grafana_ui     = "https://grafana.local"
    prometheus_ui  = "https://prometheus.local"
    artifactory_ui = "https://artifactory.local (or http://localhost:8085)"
    vault_ui       = "https://vault.local (or http://localhost:8200)"
    minio_console  = "https://minio.local (or http://localhost:9001)"
    phpldapadmin   = "https://ldap.local (or http://localhost:8082)"
  }
}

output "credentials_summary" {
  description = "Credentials cheatsheet for testing all personas"
  value = {
    keycloak_admin = "User: admin | Pass: admin"
    ldap_admin     = "DN: cn=admin,dc=example,dc=org | Pass: admin"
    vault_token    = "Token: airflow-vault-root-token-2026"
    minio_admin    = "User: minioadmin | Pass: minioadmin"
    artifactory    = "User: admin | Pass: admin123"
    breakglass_ui  = "User: breakglass | Pass: (sensitive variable breakglass_password)"
    personas = {
      alice_superadmin = "User: alice | Pass: Alice-lab-1"
      finance_owner    = "User: user_finance | Pass: Finance-lab-1"
      marketing_owner  = "User: user_marketing | Pass: Marketing-lab-1"
      logistics_owner  = "User: user_logistics | Pass: Logistics-lab-1"
      analytics_owner  = "User: user_analytics | Pass: Analytics-lab-1"
    }
  }
}
