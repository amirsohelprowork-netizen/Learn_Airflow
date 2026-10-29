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

## PostgreSQL: interactive login

PostgreSQL is running and accepts logins, but it has **no browser dashboard installed**. Port 5432 is private to the Docker network; `localhost:5432` is not published. The bundled `psql` client can connect from inside its container without installing anything on your host:

```bash
docker exec -it airflow-local-postgres psql -h 127.0.0.1 -U platform -d postgres -W
```

Enter `POSTGRES_ADMIN_PASSWORD` from `./ctl credentials`. This is the platform administrator. For the demo business data, use the read-only warehouse account:

```bash
docker exec -it airflow-local-postgres psql -h 127.0.0.1 -U warehouse -d warehouse -W
```

Enter `WAREHOUSE_PASSWORD`. Useful SQL-client commands: `\l` lists databases, `\dt` lists tables in the current database, `SELECT * FROM demo_transactions;` reads warehouse demo data, and `\q` exits.

| Account | Database | Password reference | Purpose |
| --- | --- | --- | --- |
| `platform` | `postgres` (or the database being administered) | `POSTGRES_ADMIN_PASSWORD` | Platform administration |
| `airflow` | `airflow` | `POSTGRES_PASSWORD` | Airflow metadata and Celery results |
| `warehouse` | `warehouse` | `WAREHOUSE_PASSWORD` | Read-only business demo data |
| `keycloak` | `keycloak` | `KEYCLOAK_DB_PASSWORD` | Keycloak application database |

Use the administrator or read-only account for inspection. Airflow and Keycloak manage their own database schemas. A desktop database GUI would require a separately configured connection/tunnel; no pgAdmin service is installed in this profile.

## Redis: interactive login

Redis is running with password authentication and has **no browser dashboard installed**. Its port 6379 is private; `localhost:6379` is not published.

```bash
docker exec -it airflow-local-redis redis-cli --askpass
```

Enter `REDIS_PASSWORD` from `./ctl credentials`. The ACL username is `default`, and the Celery broker uses Redis database 0. Read-only inspection commands include `PING`, `INFO clients`, `INFO keyspace`, `DBSIZE`, and `SCAN 0 COUNT 20`. Type `QUIT` to exit. Avoid modifying broker keys: they contain live Celery queue state.

## Other private protocol endpoints

These addresses are reachable by containers on Docker network `kind`; they are not host browser URLs. Kubernetes workloads use the corresponding Services in namespace `airflow`.

| Service | Docker-network endpoint | Kubernetes endpoint | Browser UI |
| --- | --- | --- | --- |
| PostgreSQL | `airflow-local-postgres:5432` | `postgres.airflow.svc.cluster.local:5432` | None installed; use `psql` above |
| Redis | `airflow-local-redis:6379` | `redis.airflow.svc.cluster.local:6379` | None installed; use `redis-cli` above |
| SMTP delivery | `airflow-local-mailpit:1025` | `mailpit.airflow.svc.cluster.local:1025` | [Mailpit inbox](http://localhost:8025); no login |
| S3 API | `airflow-local-minio:9000` | `s3.airflow.svc.cluster.local:9000` | [MinIO console](http://localhost:9001) |
| LDAP directory | `airflow-local-openldap:389` | `openldap.airflow.svc.cluster.local:389` | [phpLDAPadmin](http://localhost:8082) |

The S3 API is an application endpoint, not the MinIO console. SMTP sends captured email; the Mailpit web inbox displays it. Mailpit does not send mail to external recipients.
