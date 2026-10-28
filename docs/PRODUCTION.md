# Production deployment path

This is the proposed production counterpart to the [working local architecture](ARCHITECTURE.md). The local lab remains fully local. This guide and its Helm examples have been checked by rendering the chart; they have **not** been deployed or load-tested on production infrastructure. Disaster recovery is outside this guide's scope.

![Proposed production architecture](diagrams/production.svg)

[Full-size production diagram](diagrams/production.svg) · [editable diagram source](diagrams/production.mmd) · [production values](../deploy/production/values.example.yaml) · [ingress example](../deploy/production/ingress.example.yaml) · [local login URLs](../ENDPOINTS.md)

The production Helm chart is the **same official Apache Airflow chart, pinned to 1.22.0**, with a separate environment profile. A different Airflow distribution is not required. The [official production guide](https://airflow.apache.org/docs/helm-chart/stable/production-guide.html) recommends an external metadata database and explains connection pooling and external-secret configuration.

## Tool choices and changes

| Capability | Current local setup / change | Suitable production implementation |
| --- | --- | --- |
| Kubernetes | Single-node KinD retained | Existing supported multi-node Kubernetes, or EKS/AKS/GKE; spread replicas across nodes and failure domains |
| Airflow | Official chart, CeleryExecutor, immutable DAG image retained | Same chart and executor; private registry image pinned by digest; measured capacity and separate environments |
| Ingress | **Traefik replaced ingress-nginx** | Supported Traefik behind a load balancer; enforce HTTPS and trusted proxy settings |
| Certificates | Local OpenSSL CA replaced default cert-manager bootstrap | cert-manager with your approved issuer, or your platform's certificate service; monitored renewal |
| Metadata / results | Dedicated roles in one local PostgreSQL container | External HA PostgreSQL with verified TLS, explicit connection budget; add PgBouncer when required |
| Celery broker | Authenticated local Redis retained | Dedicated HA Redis service compatible with Celery; authenticated TLS, eviction and failover tested |
| Identity | Keycloak + OpenLDAP retained; Keycloak now uses production startup and PostgreSQL | HA Keycloak with a separate database, corporate LDAP/AD federation, MFA and restricted management access |
| LDAP management | **phpLDAPadmin retained** at localhost:8082 | Existing corporate directory tooling; keep any LDAP administration UI behind VPN/admin access |
| Secrets | Vault retained; now persistent, TLS, scoped Kubernetes login | Independently operated HA Vault, managed unseal/key custody, audit retention; External Secrets Operator for chart bootstrap secrets |
| Objects | Local MinIO retained | S3 or independently operated HA S3-compatible storage; encryption, scoped identity and retention |
| Email | Mailpit replaced default Gmail delivery | Approved authenticated TLS SMTP relay, monitored delivery and real on-call routing |
| Metrics | StatsD, Prometheus, Grafana retained | Production monitoring stack or managed equivalent; durable storage, availability alerts and Alertmanager/on-call integration |
| Worker scaling | Local KEDA retained (1–3 workers) | Start with three fixed workers in the example; enable KEDA after verifying DB scaler TLS, permissions and queue/load behavior |
| Flower | **Disabled**, no active Flower URL | Optional internal-only Celery debugging UI with authentication; Airflow and metrics remain available without it |
| Packages | Nexus made **optional**; default builds use PyPI | Approved package proxy if required (Nexus or JFrog Artifactory); private image registry for runtime releases |
| Release automation | GitHub Actions performs CI only | Build once, scan/sign and publish image, then an approved Helm or GitOps promotion; no developer workstation dependency |
| Terraform | Local provisioner-based orchestration retained | Separate production IaC root and encrypted, access-controlled remote state for the selected infrastructure |

The repository's `artifactory` command starts **Sonatype Nexus**, not JFrog Artifactory. It has not been replaced with a different package service. The [Kubernetes ingress-nginx retirement notice](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) explains the Traefik change. [Keycloak's production guidance](https://www.keycloak.org/server/configuration-production) covers TLS, clustered identity and restricted administrative endpoints. [External Secrets' Vault provider](https://external-secrets.io/latest/provider/hashicorp-vault/) documents bootstrap-secret synchronization.

For example, an AWS implementation could use EKS + RDS PostgreSQL + a compatible ElastiCache Redis deployment + S3 + ECR, while keeping Keycloak, Vault and the monitoring platform independently operated. An on-premises implementation can use multi-node Kubernetes, operated HA PostgreSQL/Redis, HA object storage and Harbor. These are alternative infrastructure choices; neither is provisioned by this repository. Choose supported, patched service versions and scan all service images; the local Vault/LDAP/Keycloak version pins are compatibility baselines, not production recommendations.

## 1. Prepare the production environment

Use a **separate cluster/context and secret store**, with at least three schedulable worker nodes for the example's replica distribution and sufficient spare capacity for upgrades. Install a policy-enforcing CNI such as Cilium or Calico, an ingress controller in `ingress-system`, and monitoring. Configure storage classes and private registry authentication as required. Confirm current component compatibility against the pinned Airflow chart and your Kubernetes version.

Create the `airflow` namespace. Apply your platform's enforced network controls: ingress only from the ingress controller and approved internal callers; egress only to DNS, required Airflow services, PostgreSQL, Redis, Vault, IdP, object storage, SMTP and approved task destinations. Chart-generated policies are not a complete outbound allowlist. The example uses internal HTTP for the Execution API; if your policy requires east-west encryption, configure and verify mesh mTLS or an equivalent transport before rollout. Never expose databases, brokers or admin consoles publicly.

Provision PostgreSQL, Redis, log storage, Vault, identity and SMTP first. Require PostgreSQL hostname/certificate verification and Redis certificate verification. Reserve DB connections for migrations and operators, including result-backend traffic. The example leaves PgBouncer disabled: enabling it requires changing connection targets and adding its configuration/statistics secrets, as described in the official chart guide; toggling a boolean alone is insufficient.

Configure Keycloak realm `airflow`, confidential client `airflow`, and the exact redirect URI `https://airflow.example.com/auth/oauth-authorized/keycloak` after replacing the domain. Keep browser and backend discovery reachable with trusted HTTPS. Map corporate groups to `Admin`/`airflow-admins` and the four `aid-<department>-auth` roles used in `config/webserver_config.py`; review privileged membership. Keep client password grants disabled. Do not import local demo users/passwords into production. Keep administration private and configure MFA/session policies.

## 2. Provision secret contracts

Create these Kubernetes Secrets in namespace `airflow` through your approved secret delivery mechanism. The values file contains references only. External Secrets can synchronize them from Vault using a dedicated identity whose permissions are distinct from DAG runtime access. Enable Kubernetes secret encryption at rest and restrict RBAC. Do not use `.local/`, commit credentials, or pass passwords in Helm CLI arguments.

| Secret name | Required key | Contract |
| --- | --- | --- |
| `airflow-metadata-secret` | `connection` | URL-encoded PostgreSQL URI, `postgresql://…`, `sslmode=verify-full`; trusted CA available in pods |
| `airflow-result-backend-secret` | `connection` | Celery result SQLAlchemy URI, `db+postgresql://…`, same TLS requirement |
| `airflow-broker-secret` | `connection` | Authenticated `rediss://…` URI with certificate verification required |
| `airflow-api-secret` | `api-secret-key` | Strong stable random API/session key shared across API replicas |
| `airflow-fernet-secret` | `fernet-key` | Valid Fernet key; use a deliberate rotation procedure |
| `airflow-jwt-secret` | `jwt-secret` | Strong stable random key shared by Airflow components |
| `airflow-runtime-secret` | `KEYCLOAK_CLIENT_SECRET` | Production confidential OIDC client secret |
| `airflow-prod-vault-ca` | `ca.crt` | Trusted issuing CA chain for Vault; mounted at `/opt/airflow/tls/ca.crt` |
| `airflow-prod-tls` | `tls.crt`, `tls.key` | `kubernetes.io/tls` certificate Secret for the real Airflow hostname |

If DB/Redis use a private CA, add that CA mount and URI/client TLS settings to your copied values. The supplied Vault CA mount alone does not configure database or Redis trust. Use a combined system/private trust bundle if overriding global request trust; do not disable verification.

Enable Vault Kubernetes authentication against the production cluster and bind role `airflow-prod` to the exact service accounts `airflow-api-server`, `airflow-scheduler`, `airflow-worker`, `airflow-dag-processor`, and `airflow-triggerer`, namespace `airflow`. Configure token review correctly and short token TTLs. Grant runtime read only on these KV v2 data paths:

```text
secret/data/airflow/prod/connections/aws_default
secret/data/airflow/prod/connections/smtp_default
secret/data/airflow/prod/connections/warehouse_default
```

Store Airflow connection objects there: `aws_default` should use workload identity where available, region and HTTPS object storage (remove the local MinIO endpoint/credentials); `smtp_default` should use your TLS relay; `warehouse_default` should use the real read-only warehouse identity and verified TLS. Do not give tasks root Vault tokens or access to chart bootstrap/signing secrets. Arrange workload identity/registry bindings for the relevant component service accounts, including those reading remote logs. Separate mutually untrusted teams into independent deployments and credentials: UI RBAC/pools do not sandbox DAG Python.

## 3. Build and render a release

Create a private environment configuration outside Git, or in a separate access-controlled deployment repository. `values.example.yaml` is **standalone**; do not layer it over the root local `values.yaml`.

```bash
cp deploy/production/values.example.yaml /secure/path/airflow-prod.yaml
cp deploy/production/ingress.example.yaml /secure/path/airflow-ingress.yaml
```

Replace every `example.com` hostname, `replace-with-*` value and the all-zero image digest. Match the ingress class to your controller. Keep the Helm release name and namespace `airflow` unless also updating the internal Execution API URL, network selectors and Vault service-account bindings. Configure image-pull credentials through chart `registry.secretName` if workload identity does not provide access. Adjust replica sizing, disruption budgets and topology spread to the actual infrastructure; the example spreads each component across hostnames, while zone spreading must be added for a multi-zone deployment.

Build and scan using the existing Dockerfile/CI quality gates, publish to your private registry, and record the returned immutable digest in your production values. The supplied GitHub workflow does not publish images or deploy anything. All Airflow components must use the same tested image, including migrations. Do not use `kind load` or `./ctl start` for production.

```bash
helm pull airflow --repo https://airflow.apache.org --version 1.22.0
helm lint airflow-1.22.0.tgz -f /secure/path/airflow-prod.yaml
helm template airflow airflow-1.22.0.tgz --namespace airflow \
  -f /secure/path/airflow-prod.yaml > /secure/path/airflow-rendered.yaml
kubectl --context YOUR_PRODUCTION_CONTEXT apply --dry-run=server \
  -f /secure/path/airflow-rendered.yaml
kubectl --context YOUR_PRODUCTION_CONTEXT apply --dry-run=server \
  -f /secure/path/airflow-ingress.yaml
```

Review the rendered image digests, Secret references, API exposure, service-account permissions, resources and network rules. All external resources and Secrets must already exist. Install required CRDs before server dry-run if you enable optional integrations.

## 4. Deploy and initialize authorization

After reviewing the actual production diff and migration plan:

```bash
helm upgrade --install airflow ./airflow-1.22.0.tgz \
  --kube-context YOUR_PRODUCTION_CONTEXT --namespace airflow \
  -f /secure/path/airflow-prod.yaml --timeout 15m
kubectl --context YOUR_PRODUCTION_CONTEXT -n airflow rollout status \
  deployment/airflow-api-server --timeout=600s
kubectl --context YOUR_PRODUCTION_CONTEXT -n airflow rollout status \
  deployment/airflow-scheduler --timeout=600s
kubectl --context YOUR_PRODUCTION_CONTEXT -n airflow exec \
  deployment/airflow-scheduler -c scheduler -- \
  python3 /opt/airflow/config/bootstrap_roles.py
kubectl --context YOUR_PRODUCTION_CONTEXT apply \
  -f /secure/path/airflow-ingress.yaml
```

This profile enables chart **post-install/post-upgrade migration hooks**. Do not add Helm `--wait` or `--atomic` to these commands: pods waiting for migrations can otherwise prevent the post-install hook from starting. Helm waits for the migration hook itself; then explicitly await all API, scheduler, DAG processor, triggerer and worker rollouts. The local launcher uses a different, explicit pre-Helm migration path and must not be reused here. Investigate a failed migration before retrying or promoting; a Helm rollback does not reverse database schema changes.

The bootstrap script creates the department roles and pools required by the bundled policy. Review its default two-slot department pool sizes before admitting real workloads. All DAGs start paused. The business DAGs use demonstration data; the finance demo hardcodes bucket `airflow-reports`, which must be replaced with your own globally unique bucket/configuration before running against production object storage. Replace demo inputs and output destinations before enabling business schedules; keep the deliberate `failure_drill` paused except during an authorized alert test.

## 5. Verify before admitting production traffic

Verify successful migrations and readiness for every replica, enforced network isolation, real HTTPS/OIDC login, actual department API denials, and Vault denial for unrelated paths. Run an approved end-to-end workload and check retries, result state, remote log retrieval, report output and real alert delivery. Exercise worker termination/restart and a node drain; measure queue latency, task throughput, resource peaks and database connections under representative load.

Provision production dashboards/alerts for scheduler heartbeat, import errors, queue age, task failures, worker availability, DB/broker health, Vault/OIDC failures and certificate expiry. The small local monitoring manifests and seven-day retention are not a production monitoring deployment. Test alert routing with the actual on-call recipient.

Only enable KEDA after the production scaler can reach PostgreSQL with certificate verification and least-privilege credentials, and scale-up/down behavior has passed a queue test. Do not reuse a pod-only CA file path in a scaler connection URI without arranging equivalent trust inside KEDA. Fixed workers are intentional in this example to avoid silently copying local non-TLS scaler assumptions.

## Boundaries of this repository

The new profile supplies chart configuration, ingress, secret contracts, deployment order and verification criteria. It does not create your production network, cluster, managed services, IAM, CNI policies or certificate issuer. The existing `terraform/` root uses a local backend and local orchestration. The S3 backend example is only input for a **separate** production root declaring `backend "s3" {}`; it cannot switch the existing local backend. Do not apply the local Terraform modules to production.

Production URLs come from your DNS choices (for example `https://airflow.example.com` and `https://sso.example.com`), not localhost. Keep Vault, LDAP administration, Grafana/Prometheus and other control panels private. No production infrastructure has been created or changed by adding these examples.
