# Local login URLs

Start the local stack with `./ctl start`, then retrieve your generated passwords with `./ctl credentials`. Import `.local/tls/ca.crt` into your browser's trusted authorities for HTTPS. Password names below refer to that command's output; no passwords are stored in this document.

| Tool | URL | Login / password reference |
| --- | --- | --- |
| Airflow | https://localhost | Keycloak SSO: `alice` / `ALICE_PASSWORD`, or `user_finance` / `FINANCE_PASSWORD` and the other department personas |
| Keycloak administration | https://localhost:8443/admin/ | `admin` / `KEYCLOAK_ADMIN_PASSWORD` |
| **phpLDAPadmin (retained)** | **http://localhost:8082** | Login DN: `cn=admin,dc=example,dc=org`; password: `LDAP_ADMIN_PASSWORD` |
| Vault | https://localhost:8200 | Local bootstrap root token in `.local/vault-init.json`; do not share this file |
| MinIO console | http://localhost:9001 | `airflow-local` / `MINIO_PASSWORD` |
| Mailpit inbox | http://localhost:8025 | No login; locally captured email |
| Grafana | http://localhost:3000 | First run `./ctl ui grafana`; `admin` / `GRAFANA_ADMIN_PASSWORD` |
| Flower | http://localhost:5555 | First run `./ctl ui flower`; `admin` / `FLOWER_PASSWORD` |
| Prometheus | http://localhost:9090 | First run `./ctl ui prometheus`; loopback port-forward, no login |
| Nexus package proxy (optional) | http://localhost:8085 | First run `./ctl artifactory start`; `admin` / `NEXUS_ADMIN_PASSWORD` |

Management listeners bind to loopback. Old `ldap.local` routes and the old Keycloak port 8081 are not the current entry points. Flower is enabled with basic authentication and exposed through a loopback-only port-forward. Traefik has no public administration dashboard. PostgreSQL, Redis and LDAP protocol ports are private service endpoints, not browser login pages.

The local `breakglass` Airflow administrator persona authenticates through Keycloak using `AIRFLOW_ADMIN_PASSWORD`; it does not bypass an unavailable identity provider.

For which tools changed and how to deploy production, see the [production tool comparison and deployment guide](docs/PRODUCTION.md). For local lifecycle and troubleshooting, see [local setup](docs/LOCAL_SETUP.md).
