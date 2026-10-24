#!/usr/bin/env bash
# ==============================================================================
# Setup & Bridge External OpenLDAP & phpLDAPadmin for Airflow
# Runs OpenLDAP as an external Docker container outside KinD cluster,
# simulating enterprise Active Directory / LDAP user and group management.
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LDAP_CONTAINER="airflow-openldap"
PHPLDAPADMIN_CONTAINER="airflow-phpldapadmin"
LDAP_PORT="389"
PHPLDAPADMIN_PORT="8082"
NAMESPACE="airflow"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}=== 1. Starting External OpenLDAP Directory Container ===${NC}"
if ! docker ps --filter "name=^/${LDAP_CONTAINER}$" --format '{{.Names}}' | grep -qx "${LDAP_CONTAINER}"; then
    if docker ps -a --filter "name=^/${LDAP_CONTAINER}$" --format '{{.Names}}' | grep -qx "${LDAP_CONTAINER}"; then
        echo "Starting existing '${LDAP_CONTAINER}' container..."
        docker start "${LDAP_CONTAINER}"
    else
        echo "Launching external OpenLDAP container '${LDAP_CONTAINER}' on port ${LDAP_PORT}..."
        docker run -d \
            --name "${LDAP_CONTAINER}" \
            --restart unless-stopped \
            -p "${LDAP_PORT}:389" \
            -v airflow-ldap-data:/var/lib/ldap \
            -v airflow-ldap-config:/etc/ldap/slapd.d \
            -e LDAP_ORGANISATION="Example Inc." \
            -e LDAP_DOMAIN="example.org" \
            -e LDAP_ADMIN_PASSWORD="admin" \
            osixia/openldap:1.5.0
    fi
else
    echo "External OpenLDAP container '${LDAP_CONTAINER}' is already running."
fi

# Connect OpenLDAP container to KinD network if present
if docker network inspect kind >/dev/null 2>&1; then
    docker network connect kind "${LDAP_CONTAINER}" 2>/dev/null || true
fi

echo "Waiting for OpenLDAP to be ready on port ${LDAP_PORT}..."
for i in {1..30}; do
    if docker exec "${LDAP_CONTAINER}" ldapsearch -x -H ldap://localhost -b "dc=example,dc=org" -D "cn=admin,dc=example,dc=org" -w admin >/dev/null 2>&1; then
        echo -e "${GREEN}OpenLDAP is responsive.${NC}"
        break
    fi
    sleep 1
done

# Seed initial LDAP structure and AD groups if not already present
if ! docker exec "${LDAP_CONTAINER}" ldapsearch -x -H ldap://localhost -b "ou=users,dc=example,dc=org" -D "cn=admin,dc=example,dc=org" -w admin >/dev/null 2>&1; then
    echo "Configuring OpenLDAP memberof overlay for groupOfNames (bidirectional AD membership)..."
    docker exec -i "${LDAP_CONTAINER}" ldapmodify -Q -Y EXTERNAL -H ldapi:/// 2>/dev/null << 'EOF' || true
dn: olcOverlay={0}memberof,olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcMemberOfGroupOC
olcMemberOfGroupOC: groupOfNames
-
replace: olcMemberOfMemberAD
olcMemberOfMemberAD: member
EOF

    echo "Seeding initial enterprise users and AD groups from k8s/ldap/bootstrap.ldif..."
    docker exec -i "${LDAP_CONTAINER}" ldapadd -x -D "cn=admin,dc=example,dc=org" -w admin < "${ROOT_DIR}/k8s/ldap/bootstrap.ldif"
    echo -e "${GREEN}OpenLDAP successfully seeded with enterprise users and AD security groups.${NC}"
else
    echo "OpenLDAP enterprise structure already initialized."
fi

echo -e "${CYAN}=== 2. Starting phpLDAPadmin Web GUI ===${NC}"
if ! docker ps --filter "name=^/${PHPLDAPADMIN_CONTAINER}$" --format '{{.Names}}' | grep -qx "${PHPLDAPADMIN_CONTAINER}"; then
    if docker ps -a --filter "name=^/${PHPLDAPADMIN_CONTAINER}$" --format '{{.Names}}' | grep -qx "${PHPLDAPADMIN_CONTAINER}"; then
        echo "Starting existing '${PHPLDAPADMIN_CONTAINER}' container..."
        docker start "${PHPLDAPADMIN_CONTAINER}"
    else
        echo "Launching external phpLDAPadmin container on port ${PHPLDAPADMIN_PORT}..."
        docker run -d \
            --name "${PHPLDAPADMIN_CONTAINER}" \
            --restart unless-stopped \
            -p "${PHPLDAPADMIN_PORT}:80" \
            -e PHPLDAPADMIN_LDAP_HOSTS="${LDAP_CONTAINER}" \
            -e PHPLDAPADMIN_HTTPS=false \
            osixia/phpldapadmin:0.9.0
    fi
else
    echo "External phpLDAPadmin container '${PHPLDAPADMIN_CONTAINER}' is already running."
fi

# Enable custom_attrs display (shows memberOf on users in templates)
docker exec -i "${PHPLDAPADMIN_CONTAINER}" bash -c '
    if ! grep -q "custom_attrs" /var/www/phpldapadmin/config/config.php; then
        echo "\$servers->setValue(\"server\",\"custom_attrs\",array(\"memberof\",\"memberOf\"));" >> /var/www/phpldapadmin/config/config.php
        service php7.3-fpm reload >/dev/null 2>&1 || true
    fi
' 2>/dev/null || true

if docker network inspect kind >/dev/null 2>&1; then
    docker network connect kind "${PHPLDAPADMIN_CONTAINER}" 2>/dev/null || true
fi

echo -e "${CYAN}=== 3. Mapping External OpenLDAP into Kubernetes ===${NC}"
if kubectl cluster-info >/dev/null 2>&1; then
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f "${ROOT_DIR}/k8s/ldap/service.yaml"
    kubectl apply -f "${ROOT_DIR}/k8s/ldap/phpldapadmin-service.yaml"
    echo -e "${GREEN}Services 'openldap' and 'phpldapadmin' mapped in namespace '${NAMESPACE}' to external host containers.${NC}"
else
    echo -e "${YELLOW}Kubernetes cluster not detected yet; skipping k8s service mapping.${NC}"
fi

echo -e "${GREEN}======================================================================${NC}"
echo -e "${GREEN}Enterprise OpenLDAP Directory is ready!${NC}"
echo -e "OpenLDAP Endpoint:  ldap://localhost:389 (Bind DN: cn=admin,dc=example,dc=org | Pass: admin)"
echo -e "phpLDAPadmin GUI:   http://localhost:8082 (Login DN: cn=admin,dc=example,dc=org | Pass: admin)"
echo -e "${GREEN}======================================================================${NC}"
