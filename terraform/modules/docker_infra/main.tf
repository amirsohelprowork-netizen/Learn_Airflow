# Docker Volumes for persistent stateful infrastructure
resource "docker_volume" "artifactory_data" {
  name = "airflow-artifactory-data"
}

resource "docker_volume" "postgres_data" {
  name = "airflow-postgres-data"
}

resource "docker_volume" "redis_data" {
  name = "airflow-redis-data"
}

resource "docker_volume" "minio_data" {
  name = "airflow-minio-data"
}

resource "docker_volume" "ldap_data" {
  name = "airflow-ldap-data"
}

resource "docker_volume" "ldap_config" {
  name = "airflow-ldap-config"
}

# 1. Sonatype Nexus 3 OSS (Central Artifact Repository)
resource "docker_container" "artifactory" {
  name    = "airflow-artifactory"
  image   = "sonatype/nexus3:latest"
  restart = "unless-stopped"

  env = [
    "INSTALL4J_ADD_VM_PARAMS=-Xms1024m -Xmx2048m -XX:MaxDirectMemorySize=1024m"
  ]

  ports {
    internal = 8081
    external = var.artifactory_ui_port
  }

  ports {
    internal = 5000
    external = var.artifactory_docker_port
  }

  volumes {
    volume_name    = docker_volume.artifactory_data.name
    container_path = "/nexus-data"
  }

  networks_advanced {
    name = var.network_name
  }
}

# 2. PostgreSQL 16 (Airflow Metadata Database)
resource "docker_container" "postgres" {
  name    = "airflow-postgres"
  image   = "postgres:16-alpine"
  restart = "unless-stopped"

  env = [
    "POSTGRES_USER=airflow",
    "POSTGRES_PASSWORD=airflow",
    "POSTGRES_DB=airflow"
  ]

  ports {
    internal = 5432
    external = var.postgres_port
  }

  volumes {
    volume_name    = docker_volume.postgres_data.name
    container_path = "/var/lib/postgresql/data"
  }

  networks_advanced {
    name = var.network_name
  }
}

# 3. Redis 7 (Celery Message Broker)
resource "docker_container" "redis" {
  name    = "airflow-redis"
  image   = "redis:7-alpine"
  restart = "unless-stopped"

  ports {
    internal = 6379
    external = var.redis_port
  }

  volumes {
    volume_name    = docker_volume.redis_data.name
    container_path = "/data"
  }

  networks_advanced {
    name = var.network_name
  }
}

# 4. HashiCorp Vault (External Secrets Engine)
resource "docker_container" "vault" {
  name    = "airflow-vault"
  image   = "hashicorp/vault:1.15.6"
  restart = "unless-stopped"
  capabilities {
    add = ["IPC_LOCK"]
  }

  env = [
    "VAULT_DEV_ROOT_TOKEN_ID=airflow-vault-root-token-2026",
    "VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200",
    "VAULT_UI=true"
  ]

  ports {
    internal = 8200
    external = var.vault_port
  }

  networks_advanced {
    name = var.network_name
  }
}

# 5. MinIO S3 (Remote Task Logs & Backups Storage)
resource "docker_container" "minio" {
  name    = "airflow-minio"
  image   = "cleanstart/minio:latest"
  restart = "unless-stopped"
  user    = "root"
  command = ["server", "/data", "--console-address", ":9001"]

  env = [
    "MINIO_ROOT_USER=minioadmin",
    "MINIO_ROOT_PASSWORD=minioadmin"
  ]

  ports {
    internal = 9000
    external = var.minio_port
  }

  ports {
    internal = 9001
    external = var.minio_console_port
  }

  volumes {
    volume_name    = docker_volume.minio_data.name
    container_path = "/data"
  }

  networks_advanced {
    name = var.network_name
  }
}

# 6. OpenLDAP (Simulated Corporate Active Directory)
resource "docker_container" "openldap" {
  name    = "airflow-openldap"
  image   = "osixia/openldap:1.5.0"
  restart = "unless-stopped"

  env = [
    "LDAP_ORGANISATION=Example Inc.",
    "LDAP_DOMAIN=example.org",
    "LDAP_ADMIN_PASSWORD=admin"
  ]

  ports {
    internal = 389
    external = var.ldap_port
  }

  volumes {
    volume_name    = docker_volume.ldap_data.name
    container_path = "/var/lib/ldap"
  }

  volumes {
    volume_name    = docker_volume.ldap_config.name
    container_path = "/etc/ldap/slapd.d"
  }

  networks_advanced {
    name = var.network_name
  }
}

# 7. phpLDAPadmin (LDAP Web GUI)
resource "docker_container" "phpldapadmin" {
  name    = "airflow-phpldapadmin"
  image   = "osixia/phpldapadmin:0.9.0"
  restart = "unless-stopped"

  env = [
    "PHPLDAPADMIN_LDAP_HOSTS=airflow-openldap",
    "PHPLDAPADMIN_HTTPS=false"
  ]

  ports {
    internal = 80
    external = var.phpldapadmin_port
  }

  networks_advanced {
    name = var.network_name
  }

  depends_on = [docker_container.openldap]
}

# 8. Keycloak 26 (Enterprise OIDC Identity Provider)
resource "docker_container" "keycloak" {
  name    = "airflow-keycloak"
  image   = "quay.io/keycloak/keycloak:26.0.0"
  restart = "unless-stopped"
  command = ["start-dev", "--import-realm"]

  env = [
    "KEYCLOAK_ADMIN=admin",
    "KEYCLOAK_ADMIN_PASSWORD=admin",
    "KC_HTTP_PORT=8080",
    "KC_HOSTNAME=http://localhost:8081",
    "KC_HOSTNAME_STRICT=false",
    "KC_HOSTNAME_BACKCHANNEL_DYNAMIC=true",
    "KC_HTTP_ENABLED=true",
    "KC_HEALTH_ENABLED=true"
  ]

  ports {
    internal = 8080
    external = var.keycloak_port
  }

  volumes {
    host_path      = "${var.project_root}/k8s/keycloak/realm-airflow.json"
    container_path = "/opt/keycloak/data/import/airflow-realm.json"
    read_only      = true
  }

  networks_advanced {
    name = var.network_name
  }

  depends_on = [docker_container.openldap]
}

# Post-configuration: Initialize MinIO log buckets
resource "null_resource" "minio_buckets" {
  depends_on = [docker_container.minio]

  provisioner "local-exec" {
    command = "docker exec ${docker_container.minio.name} mkdir -p /data/airflow-logs /data/airflow-backups 2>/dev/null || true"
  }
}

# Post-configuration: Seed OpenLDAP tree
resource "null_resource" "ldap_seed" {
  depends_on = [docker_container.openldap]

  provisioner "local-exec" {
    command = "bash ${var.project_root}/scripts/setup-ldap.sh 2>/dev/null || true"
  }
}

# Post-configuration: Configure Nexus 3 OSS Proxies & Accept CE EULA
resource "null_resource" "artifactory_setup" {
  depends_on = [docker_container.artifactory]

  provisioner "local-exec" {
    command = "bash ${var.project_root}/scripts/setup-artifactory.sh"
  }
}

# Post-configuration: Seed HashiCorp Vault secrets & Kubernetes auth
resource "null_resource" "vault_setup" {
  depends_on = [docker_container.vault]

  provisioner "local-exec" {
    command = "bash ${var.project_root}/scripts/setup-vault.sh"
  }
}
