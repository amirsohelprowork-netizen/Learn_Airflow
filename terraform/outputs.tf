output "cluster_name" {
  value = module.kind_cluster.cluster_name
}
output "web_consoles" {
  value = {
    airflow  = "https://localhost"
    keycloak = "https://localhost:8443"
    inbox    = "http://localhost:8025"
    vault    = "https://localhost:8200"
  }
}
output "credentials_location" {
  value = "Generated locally in .local/secrets.json; use ./ctl credentials."
}
