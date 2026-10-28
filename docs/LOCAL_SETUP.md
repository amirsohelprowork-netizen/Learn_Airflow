# Hardened local Airflow

This is a production-like learning environment for trusted DAG authors on one machine. It requires no cloud account, hosted identity provider, Gmail, external secret store, or remote DAG repository. Images, Python packages, and Helm charts are downloaded during the initial build. Once cached, tasks and integrations run locally; fully air-gapped installation requires preloading those artifacts.

See [the architecture review](ARCHITECTURE.md) for the runtime topology, authentication flow, and deployment diagrams.

## Prerequisites and first start

Use Linux x86_64 with Docker Engine access, Python 3.12 (host Python 3.10+ also works), OpenSSL, KinD, kubectl, Helm 3, and Terraform 1.5+ if using IaC. Docker must support the pinned Kubernetes 1.34 node image. Startup installs a checksum-pinned KinD 0.30 CLI into `.local/bin` without replacing your system CLI. Allow approximately 8–10 GiB available RAM for the stack and enough disk for images. Nexus is optional and consumes additional memory. Host ports 80, 443, 8443, 8025, 8200, 9001, and 8082 must be available.

```bash
./ctl init
./ctl start
./ctl credentials
```

Open **https://localhost** and sign in through Keycloak. `alice` is the LDAP administrator persona. `user_finance`, `user_marketing`, `user_logistics`, and `user_analytics` are department users. Their generated passwords are named `ALICE_PASSWORD`, `FINANCE_PASSWORD`, etc. in `./ctl credentials`. The Keycloak-local administrator persona `breakglass` uses `AIRFLOW_ADMIN_PASSWORD`; it does not bypass an unavailable Keycloak service. The Keycloak management console uses `admin` / `KEYCLOAK_ADMIN_PASSWORD`.

Import `.local/tls/ca.crt` into your browser's trusted certificate authorities before signing in. This avoids disabling TLS verification. No hosts-file changes or public wildcard DNS service is required. `https://airflow.local` also works if you map it to 127.0.0.1 yourself.

## Local endpoints

| Service | Address | Access |
| --- | --- | --- |
| Airflow | https://localhost | OIDC login |
| Keycloak | https://localhost:8443 | Generated administrator credentials |
| Email inbox | http://localhost:8025 | Local captured mail; no email leaves the machine |
| Vault | https://localhost:8200 | Bootstrap root token in `.local/vault-init.json` |
| MinIO console | http://localhost:9001 | `airflow-local` / `MINIO_PASSWORD` |
| LDAP admin | http://localhost:8082 | `cn=admin,dc=example,dc=org` / `LDAP_ADMIN_PASSWORD` |
| Grafana | `./ctl ui grafana`, then http://localhost:3000 | `admin` / `GRAFANA_ADMIN_PASSWORD` |
| Flower | `./ctl ui flower`, then http://localhost:5555 | `admin` / `FLOWER_PASSWORD` |
| Prometheus | `./ctl ui prometheus`, then http://localhost:9090 | Loopback port-forward |
| Nexus (optional) | `./ctl artifactory start`, then http://localhost:8085 | `admin` / `NEXUS_ADMIN_PASSWORD` |

Host listeners bind to loopback. PostgreSQL and Redis have no published host ports. Service bridge endpoints are derived from running Docker container IPs, not a hardcoded gateway. Internal PostgreSQL, Redis, LDAP, SMTP and S3 traffic is on the private local Docker network; it is not all encrypted. Vault and OIDC traffic use verified TLS. This deliberate local network trust assumption is not a configuration for exposing the environment on a LAN or the Internet.

## Persistent credentials and storage

`.local/` is excluded from Git, Docker build contexts, and repository bundles. The directory is owner-only; generated credentials and the Vault bootstrap response are mode 0600. The server key must be readable by non-root service containers, but is protected on the host by its owner-only parent directory. Only the server certificate/key are mounted into services; the CA signing key is not mounted.

Keep `.local/` together with its named Docker volumes. Never delete or regenerate it while retaining service databases: those databases contain the corresponding credentials. Initialization preserves existing keys. Vault uses persistent Raft storage, an audit log, and Kubernetes login; Airflow receives no root Vault token. The single local unseal key and root token remain on disk to make local restart automated. This is a local convenience, not production key custody.

All new containers and data volumes use `airflow-local-...` names. Old `airflow-...` lab containers and volumes are not removed or imported. Starting old services concurrently can cause port conflicts. Migrate business data deliberately; do not attach old databases to the hardened setup and expect new passwords to work.

`./ctl stop` stops services and the KinD node, retaining data. `./ctl start` resumes them and reconciles configuration. Deleting the KinD cluster removes in-cluster monitoring storage; external named volumes persist. No destructive reset command is included.

## DAG releases and correctness

DAGs, runtime policy and configuration are packaged into a content-addressed image. Package compatibility is checked during the build; pip and uv are removed from the final runtime. Add task dependencies to the image and rebuild, rather than installing packages in running workers. Editing them requires `./ctl start` to build and load a new release. A running pod does not automatically execute changes pushed to Git. A rollout uses one immutable image reference throughout the Airflow deployment. Database migrations run in that exact image before Helm applies the release; they do not depend on post-install hooks or mutable Kubernetes Job templates. Helm is pinned to chart 1.22.0; ingress and KEDA are pinned separately.

The workflows contain **demonstration business data**. They are not real finance, logistics, or marketing applications. Finance writes a run-specific report into `airflow-reports`; a retry writes the same key, while another run gets a different key. An upload error fails the task and prevents successful Asset publication. Analytics reads the seeded `demo_transactions` table using a separate warehouse role and fails on database errors. It has no need for metadata database access.

Policies enforce valid department ownership, replace unauthorized DAG grants, apply timeouts/retries, and assign concurrency pools. Pools and UI/API RBAC are not a sandbox for malicious DAG authors. Runtime service accounts share the three approved connection paths in Vault. Use separate deployments, identities, and secret policies for teams that do not trust one another.

## Verification and operations

```bash
./ctl test --static      # Host tests; unavailable Airflow integration is explicitly skipped
./ctl test               # Build if needed and run the full suite in the exact runtime
./ctl ci                 # Python, individual Bash files, Terraform, rendered Helm, runtime
./ctl test-auth          # OIDC login, group claims, and actual Airflow API access denial for other teams
./ctl smoke              # Live HTTPS, health, protected API, DAG imports, Vault scope
./ctl smoke --run-dag    # Also trigger and await the finance workflow
./ctl test-alert         # Deliberate task failure; inspect http://localhost:8025
./ctl scan               # Gate fixable high/critical vulnerabilities; downloads scanner DB
./ctl autoscaler
./ctl logs worker
```

`./ctl ci` needs host PyYAML (`python3 -m pip install PyYAML==6.0.2`) and downloads pinned charts/providers. CI installs the actual Airflow runtime and fails if it cannot import the DAGs. Do not treat host-only tests as the runtime gate.

Grafana provisions scheduler heartbeat and DAG import alerts. Prometheus stores seven days of metrics on a PVC, and Grafana keeps its database on a separate PVC. Each uses a single instance with a Recreate upgrade strategy to avoid concurrent writers to local storage. Airflow logs are stored in local S3 with a 30-day lifecycle. The Helm cleanup CronJob limits metadata history. These limits should be adjusted to the workload. Delivery tests are captured in Mailpit; there is no external on-call service.

Flower is enabled for Celery worker/task inspection. Use `./ctl ui flower` and sign in with `admin` / `FLOWER_PASSWORD` from `./ctl credentials`. Its Kubernetes Service is private; the port-forward binds only to 127.0.0.1.

KEDA uses the chart-generated database scaler and the same concurrency value as Celery (two processes per worker). It keeps one worker and permits three. Department pools have two slots each. Size these limits using real workloads before increasing them. Multiple scheduler/API replicas share one physical machine; this setup does not provide host availability guarantees. The default KinD CNI does not enforce Kubernetes NetworkPolicy; policies are rendered for portability, not claimed as an enforced local security boundary.

## Terraform entry point

Use one lifecycle owner for a cluster: shell **or** Terraform. Both use the same bootstrap scripts and pinned settings; Terraform is local orchestration with provisioners, not fully declarative management of every service.

```bash
./ctl terraform init
./ctl terraform plan
./ctl terraform apply
```

The backend is now local, so bootstrapping does not depend on an S3 service being provisioned by the same stack. State and secrets stay on your machine. Existing installations that previously initialized the MinIO backend must keep a copy of their old state and use a separate fresh checkout/state directory for this profile; do not migrate the old state or apply a destroy plan against old lab volumes. Validation uses a temporary `TF_DATA_DIR` and never needs to access old state. Terraform destroy removes its KinD cluster; external service volumes and `.local/` are retained.

Changes to code/configuration trigger bootstrap and deployment reconciliation. Unexpected manual drift inside external services is not detected by Terraform provisioners; rerun the appropriate script or `./ctl start`. Do not run `terraform destroy` against a cluster started and managed outside Terraform.

## Upgrades and limits

The service image digests make the tested setup reproducible; a pin does not establish that an image has no vulnerabilities. Review and scan service images when updating the platform. The current compatibility baseline retains the existing Vault, LDAP, and Keycloak major versions; the runtime image scan does not certify those external service images. Scan them explicitly with `./ctl scan <image>` before treating this as a deployment candidate. This environment intentionally leaves disaster recovery out of scope. It also does not demonstrate hostile-tenant isolation, hardware redundancy, or a load-tested production capacity claim.
