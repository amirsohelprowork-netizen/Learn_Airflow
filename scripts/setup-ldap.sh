#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
ensure_container airflow-local-openldap \
    -v airflow-local-ldap-data:/var/lib/ldap -v airflow-local-ldap-config:/etc/ldap/slapd.d \
    -e LDAP_ORGANISATION='Local Airflow' -e LDAP_DOMAIN=example.org \
    -e LDAP_ADMIN_PASSWORD="${LDAP_ADMIN_PASSWORD}" osixia/openldap:1.5.0@sha256:18742e9c449c9c1afe129d3f2f3ee15fb34cc43e5f940a20f3399728f41d7c28
wait_for OpenLDAP 60 docker exec airflow-local-openldap ldapsearch -x -H ldap://localhost \
    -b dc=example,dc=org -D cn=admin,dc=example,dc=org -w "${LDAP_ADMIN_PASSWORD}"
if ! docker exec airflow-local-openldap ldapsearch -x -H ldap://localhost -b ou=users,dc=example,dc=org \
    -D cn=admin,dc=example,dc=org -w "${LDAP_ADMIN_PASSWORD}" >/dev/null 2>&1; then
    docker exec -i airflow-local-openldap ldapadd -x -D cn=admin,dc=example,dc=org \
        -w "${LDAP_ADMIN_PASSWORD}" < "${ROOT_DIR}/.local/bootstrap.ldif"
fi
ensure_container airflow-local-phpldapadmin -p 127.0.0.1:8082:80 \
    -e PHPLDAPADMIN_LDAP_HOSTS=airflow-local-openldap -e PHPLDAPADMIN_HTTPS=false osixia/phpldapadmin:0.9.0@sha256:d112b82be1336f91e028b0348755133fda333992355b533419355a65c32ff9ad
