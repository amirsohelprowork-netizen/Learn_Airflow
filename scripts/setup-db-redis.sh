#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
ensure_container airflow-local-postgres \
    -e POSTGRES_USER=platform -e POSTGRES_PASSWORD="${POSTGRES_ADMIN_PASSWORD}" \
    -e POSTGRES_DB=postgres -v airflow-local-postgres-data:/var/lib/postgresql/data postgres:16-alpine@sha256:721873c34ceb9f8d8fc265984940dc982404c105f19ad51be9fdc5970a6080ea
wait_for PostgreSQL 60 docker exec airflow-local-postgres pg_isready -U platform -d postgres
# Generated passwords contain only hexadecimal characters. Do not accept arbitrary SQL input here.
docker exec -i airflow-local-postgres psql -v ON_ERROR_STOP=1 -U platform -d postgres <<SQL
SELECT 'CREATE ROLE airflow LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname='airflow')\gexec
SELECT 'CREATE ROLE warehouse LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname='warehouse')\gexec
SELECT 'CREATE ROLE keycloak LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname='keycloak')\gexec
ALTER ROLE airflow PASSWORD '${POSTGRES_PASSWORD}';
ALTER ROLE warehouse PASSWORD '${WAREHOUSE_PASSWORD}';
ALTER ROLE keycloak PASSWORD '${KEYCLOAK_DB_PASSWORD}';
SELECT 'CREATE DATABASE airflow OWNER airflow' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='airflow')\gexec
SELECT 'CREATE DATABASE warehouse OWNER platform' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='warehouse')\gexec
SELECT 'CREATE DATABASE keycloak OWNER keycloak' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='keycloak')\gexec
REVOKE ALL ON DATABASE airflow FROM PUBLIC;
REVOKE ALL ON DATABASE keycloak FROM PUBLIC;
ALTER DATABASE warehouse OWNER TO platform;
REVOKE ALL ON DATABASE warehouse FROM PUBLIC;
GRANT CONNECT ON DATABASE warehouse TO warehouse;
SQL
docker exec -i airflow-local-postgres psql -v ON_ERROR_STOP=1 -U platform -d warehouse <<'SQL'
CREATE TABLE IF NOT EXISTS demo_transactions (transaction_id integer PRIMARY KEY, amount numeric(14,2) NOT NULL);
INSERT INTO demo_transactions VALUES (1,100.00),(2,250.00),(3,50.00),(4,600.00) ON CONFLICT DO NOTHING;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO warehouse;
GRANT SELECT ON demo_transactions TO warehouse;
SQL
ensure_container airflow-local-redis -v airflow-local-redis-data:/data \
    redis:7-alpine@sha256:858f009f9709ce576febc734aa78b8f6d624b82571f9ddb6bda4377c833b3499 redis-server --appendonly yes --requirepass "${REDIS_PASSWORD}"
wait_for Redis 30 docker exec -e REDISCLI_AUTH="${REDIS_PASSWORD}" airflow-local-redis redis-cli ping
