# Apache Airflow 3 — Enterprise Kubernetes Lab

> Production-grade **Apache Airflow 3.3.2** running on local Kubernetes (**KinD**),
> wired to a full enterprise security & infrastructure stack:
> **OpenLDAP → Keycloak OIDC SSO → Dynamic Owner-Based RBAC**,
> **HashiCorp Vault** secrets management, **MinIO S3** remote logging,
> external **PostgreSQL 16** + **Redis 7**, and **Gmail SMTP** failure alerts.

Everything runs locally with a single command — no cloud accounts required.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
  - [High-Level Topology](#high-level-topology)
  - [Compute & Platform Layer (KinD Cluster)](#compute--platform-layer-kind-cluster)
  - [External Infrastructure (Docker Containers)](#external-infrastructure-docker-containers)
  - [Data & Request Flow](#data--request-flow)
- [TLS Ingress & Automated Certificate Management](#tls-ingress--automated-certificate-management)
- [Worker Autoscaling — KEDA](#worker-autoscaling--keda)
- [Observability Stack — Prometheus & Grafana](#observability-stack--prometheus--grafana)
- [RBAC Architecture — Owner-Based Dynamic Access Control](#rbac-architecture--owner-based-dynamic-access-control)
  - [The Identity Chain: LDAP → Keycloak → Airflow](#the-identity-chain-ldap--keycloak--airflow)
  - [How It Works End-to-End](#how-it-works-end-to-end)
  - [DAG Authoring Convention](#dag-authoring-convention)
- [Secrets Management — HashiCorp Vault](#secrets-management--hashicorp-vault)
- [Remote Logging — MinIO S3](#remote-logging--minio-s3)
- [Failure Alerting — Gmail SMTP](#failure-alerting--gmail-smtp)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Access Endpoints & Credentials](#access-endpoints--credentials)
- [CLI Reference (`./ctl`)](#cli-reference-ctl)
- [Project Structure](#project-structure)
- [DAG Development Rules](#dag-development-rules)
- [Troubleshooting](#troubleshooting)

---

## Architecture Overview

The lab mirrors an enterprise deployment pattern where **stateful infrastructure
services live outside the compute cluster** and are bridged in via headless
Kubernetes Services + Endpoints. Airflow's compute workloads (scheduler, workers,
API server, DAG processor, triggerer), platform controllers (NGINX Ingress,
cert-manager CA, KEDA autoscaler), and observability (Prometheus + Grafana) run
inside a KinD cluster, while databases, brokers, identity providers, and secret
stores run as standalone Docker containers.

### High-Level Topology

```mermaid
graph TB
    subgraph CLIENT["Clients & Workstations"]
        BROWSER["Developer Browser / CLI<br/><i>https://airflow.local | https://auth.local</i>"]
    end

    subgraph KIND["KinD Cluster — airflow-local"]
        direction TB

        subgraph INGRESS_LAYER["Ingress & Security Layer (TLS)"]
            ING["NGINX Ingress Controller<br/><i>Terminates TLS (Port 80/443)</i>"]
            CERT["cert-manager<br/><i>Internal Root CA Issuer</i>"]
        end

        subgraph AIRFLOW_LAYER["Airflow Compute Layer (namespace/airflow)"]
            API["API Server<br/><i>x2 replicas (FastAPI/Uvicorn)</i>"]
            SCH["Scheduler<br/><i>x2 replicas (HA)</i>"]
            DAG["DAG Processor<br/><i>x1 replica (Airflow 3 standalone)</i>"]
            WRK["Celery Workers<br/><i>Dynamic 1-5 replicas (KEDA HPA)</i>"]
            TRG["Triggerer<br/><i>x1 replica (async deferral)</i>"]
            FLW["Flower<br/><i>Celery Monitor</i>"]
            STATSD["StatsD Exporter<br/><i>Prometheus Metrics Bridge</i>"]
            GIT["git-sync<br/><i>SSH Sidecar (30s poll)</i>"]
        end

        subgraph AUTOSCALE_LAYER["Autoscaling Layer (namespace/keda)"]
            KEDA["KEDA Operator + HPA<br/><i>Watches PostgreSQL Task Queue</i>"]
        end

        subgraph OBS_LAYER["Observability Layer (namespace/observability)"]
            PROM["Prometheus<br/><i>Scrapes StatsD every 5s</i>"]
            GRAF["Grafana 11<br/><i>Airflow Health Dashboards</i>"]
        end
    end

    subgraph EXT["External Infrastructure (Docker Containers)"]
        direction LR
        PG["PostgreSQL 16<br/><i>Metadata DB</i>"]
        RD["Redis 7<br/><i>Celery Broker</i>"]
        KC["Keycloak 26<br/><i>OIDC IdP</i>"]
        LDAP["OpenLDAP<br/><i>Enterprise Directory</i>"]
        VLT["HashiCorp Vault<br/><i>Secrets Engine</i>"]
        MINIO["MinIO<br/><i>S3-compatible Storage</i>"]
        PHA["phpLDAPadmin<br/><i>LDAP Web GUI</i>"]
    end

    GMAIL["Gmail SMTP<br/><i>smtp.gmail.com:587</i>"]
    GH["GitHub<br/><i>DAG Source Repo</i>"]

    BROWSER --> ING
    ING -->|TLS SNI airflow.local| API
    ING -->|TLS SNI auth.local| KC
    ING -->|TLS SNI flower.local| FLW
    ING -->|TLS SNI grafana.local| GRAF

    CERT -.->|Auto-provisions TLS Secrets| ING

    API --- PG
    SCH --- PG
    SCH --- RD
    WRK --- PG
    WRK --- RD
    KEDA -->|Monitors task_instance queue| PG
    KEDA -->|Scales replicas| WRK

    API --- KC
    KC --- LDAP
    SCH --- VLT
    WRK --- VLT
    WRK --- MINIO
    SCH --- MINIO
    WRK --> GMAIL
    GIT --> GH

    SCH -.->|StatsD UDP 9125| STATSD
    WRK -.->|StatsD UDP 9125| STATSD
    STATSD -.->|Scrapes HTTP 9102| PROM
    PROM -->|Datasource| GRAF
```

### Compute & Platform Layer (KinD Cluster)

Workloads are partitioned across Kubernetes namespaces (`airflow`, `keda`, `observability`, `ingress-nginx`, `cert-manager`):

| Component | Namespace | Replicas | Role |
|:---|:---|:---:|:---|
| **API Server** | `airflow` | 2 | Airflow 3 FastAPI/Uvicorn UI & REST API, serves web interface |
| **Scheduler** | `airflow` | 2 | Parses DAGs, schedules task instances, manages DAG run lifecycle |
| **DAG Processor** | `airflow` | 1 | Standalone process applying `dag_policy` dynamic RBAC policies |
| **Celery Workers** | `airflow` | 1–5 (auto) | Autoscaled dynamically by KEDA based on queued/running tasks |
| **Triggerer** | `airflow` | 1 | Monitors deferred tasks with async sensors and triggers |
| **Flower** | `airflow` | 1 | Real-time Celery monitoring dashboard |
| **StatsD Exporter** | `airflow` | 1 | Ingests native Airflow StatsD metrics and serves Prometheus endpoints |
| **git-sync** | `airflow` | sidecar | Pulls DAG files from GitHub every 30 seconds via SSH |
| **KEDA Operator** | `keda` | 1 | Event-driven autoscaler querying Airflow PostgreSQL task queue |
| **Prometheus** | `observability` | 1 | Time-series metrics engine scraping StatsD exporter every 5s |
| **Grafana** | `observability` | 1 | Real-time operational dashboard visualizing scheduler, tasks, and worker health |
| **NGINX Ingress** | `ingress-nginx` | 1 | Edge reverse proxy terminating TLS for all cluster services |
| **cert-manager** | `cert-manager` | 3 | Automated X.509 certificate provisioning via internal Root CA Issuer |

All components have **resource limits**, **PodDisruptionBudgets**, and
**NetworkPolicies** configured. The API Server is exposed via `NodePort 30080`,
mapped to `localhost:8080` through the KinD port mapping.

### External Infrastructure (Docker Containers)

These services run as standalone Docker containers on the host machine, connected
to the KinD `kind` network. Each is bridged into the cluster via a headless
Kubernetes Service with a static Endpoints resource pointing to `172.18.0.1`
(the KinD gateway IP).

| Service | Image | Host Port | In-Cluster DNS | Purpose |
|:---|:---|:---:|:---|:---|
| **PostgreSQL 16** | `postgres:16-alpine` | `5432` | `postgres.airflow.svc.cluster.local:5432` | Airflow metadata database |
| **Redis 7** | `redis:7-alpine` | `6379` | `redis.airflow.svc.cluster.local:6379` | Celery task broker |
| **Keycloak 26** | `quay.io/keycloak/keycloak:26.0.0` | `8081` | `keycloak.airflow.svc.cluster.local:8080` | OpenID Connect Identity Provider |
| **OpenLDAP** | `osixia/openldap:1.5.0` | `389` | `openldap.airflow.svc.cluster.local:389` | Enterprise directory (users & AD groups) |
| **phpLDAPadmin** | `osixia/phpldapadmin:0.9.0` | `8082` | — | Web GUI for LDAP management |
| **HashiCorp Vault** | `hashicorp/vault:1.15.6` | `8200` | `vault.airflow.svc.cluster.local:8200` | Secrets engine (KV v2, K8s Auth) |
| **MinIO** | `cleanstart/minio:latest` | `9000`/`9001` | `s3.airflow.svc.cluster.local:9000` | S3-compatible object storage for logs |

### Data & Request Flow

```mermaid
sequenceDiagram
    participant User as 👤 User (Browser)
    participant API as Airflow API Server
    participant KC as Keycloak (OIDC)
    participant LDAP as OpenLDAP
    participant SCH as Scheduler
    participant DP as DAG Processor
    participant Redis as Redis (Broker)
    participant Worker as Celery Worker
    participant PG as PostgreSQL
    participant Vault as HashiCorp Vault
    participant S3 as MinIO (S3)
    participant Gmail as Gmail SMTP

    User->>API: GET /login → "Sign in with Keycloak"
    API->>KC: OIDC Authorization Code Flow
    KC->>LDAP: Validate credentials (LDAP federation)
    LDAP-->>KC: Authenticated + group memberships
    KC-->>API: ID Token + Access Token (groups claim)
    API->>API: Map groups → Airflow roles (AUTH_ROLES_MAPPING)
    API-->>User: Authenticated session (filtered DAG list)

    Note over DP,PG: DAG Parsing (Background)
    DP->>DP: Parse DAG files from git-sync volume
    DP->>DP: Execute dag_policy() → bind owner to AD role
    DP->>PG: Store DAG metadata + access_control

    Note over User,Gmail: Task Execution
    User->>API: Trigger DAG Run
    API->>PG: Create DagRun record
    SCH->>PG: Pick up DagRun, create TaskInstances
    SCH->>Redis: Enqueue task to Celery
    Worker->>Redis: Dequeue task
    Worker->>Vault: Fetch secrets (K8s ServiceAccount auth)
    Worker->>Worker: Execute task
    Worker->>S3: Upload task logs
    Worker->>PG: Update TaskInstance state

    alt Task Fails
        Worker->>Gmail: Send failure alert (STARTTLS)
        Gmail-->>User: 📧 Email notification
    end
```

---

## TLS Ingress & Automated Certificate Management

In enterprise environments, internal web services are never exposed over raw HTTP or direct NodePorts. This lab implements a production **Ingress & TLS termination architecture** using:
- **NGINX Ingress Controller**: Edge reverse proxy routing HTTP/HTTPS traffic to internal services.
- **cert-manager**: Kubernetes-native certificate controller managing the full X.509 lifecycle.
- **Internal Enterprise Root CA**: A dedicated `ClusterIssuer` (`airflow-ca-issuer`) that automatically issues and rotates TLS certificates.

```mermaid
flowchart LR
    subgraph Client["Developer Workstation"]
        REQ["HTTPS Request<br/><i>https://airflow.local</i>"]
    end

    subgraph Cluster["KinD Kubernetes Cluster"]
        ING["NGINX Ingress Controller<br/><i>Port 80/443</i>"]
        CM["cert-manager<br/><i>ClusterIssuer (airflow-ca-issuer)</i>"]
        SEC["Secret: airflow-tls-secret<br/><i>tls.crt + tls.key</i>"]

        SVC_AIRFLOW["Service: airflow-api-server:8080"]
        SVC_KC["Service: keycloak:8080"]
        SVC_GRAF["Service: grafana:3000"]
    end

    REQ -->|SNI: airflow.local| ING
    CM -->|Issues & Signs| SEC
    SEC -.->|Mounted into| ING
    ING -->|Reverse Proxy| SVC_AIRFLOW
    ING -->|Reverse Proxy| SVC_KC
    ING -->|Reverse Proxy| SVC_GRAF
```

### Ingress Routing & TLS Matrix

| Service | Short Domain (`/etc/hosts`) | Instant Wildcard URL (Zero Config) | Target Service | TLS Secret |
|:---|:---|:---|:---|:---|
| **Airflow Web UI** | `https://airflow.local` | `https://airflow.172.18.0.2.nip.io` | `airflow-api-server:8080` | `airflow-tls-secret` |
| **Keycloak SSO** | `https://auth.local` | `https://auth.172.18.0.2.nip.io` | `keycloak:8080` | `keycloak-tls-secret` |
| **Flower Monitor** | `https://flower.local` | `https://flower.172.18.0.2.nip.io` | `airflow-flower:5555` | `flower-tls-secret` |
| **Grafana UI** | `https://grafana.local` | `https://grafana.172.18.0.2.nip.io` | `grafana:3000` | `grafana-tls-secret` |
| **Prometheus UI** | `https://prometheus.local` | `https://prometheus.172.18.0.2.nip.io` | `prometheus:9090` | `prometheus-tls-secret` |
| **HashiCorp Vault** | `https://vault.local` | `https://vault.172.18.0.2.nip.io` | `vault:8200` | `vault-tls-secret` |
| **MinIO Console** | `https://minio.local` | `https://minio.172.18.0.2.nip.io` | `s3:9001` | `minio-tls-secret` |
| **phpLDAPadmin** | `https://ldap.local` | `https://ldap.172.18.0.2.nip.io` | `phpldapadmin:80` | `ldap-tls-secret` |

> [!TIP]
> **Two ways to access HTTPS:**
> 1. **Immediate Zero-Config**: Open the `.nip.io` URLs in your browser right now — no system edits required.
> 2. **Short Domains**: Run `sudo ./ctl hosts` to automatically append `172.18.0.2 airflow.local ...` to `/etc/hosts`.

---

## Worker Autoscaling — KEDA

Rather than maintaining a static pool of Celery worker pods, the cluster runs **KEDA (Kubernetes Event-driven Autoscaling)** to dynamically scale workers based on workload demand.

```mermaid
flowchart TD
    subgraph Airflow["Airflow Workload Activity"]
        TI["Task Instances Queued / Running"]
        PG[(PostgreSQL Metadata DB)]
        TI -->|State: queued / running| PG
    end

    subgraph KEDA_Control["KEDA Controller Loop"]
        SO["ScaledObject (airflow-worker)"]
        AUTH["TriggerAuthentication (DB secret)"]
        HPA["Horizontal Pod Autoscaler (HPA)"]

        AUTH --> SO
        SO -->|Polls every 5s| PG
        SO -->|Calculates replica count| HPA
    end

    subgraph Workers["Celery Worker Deployment"]
        W1["Worker Pod 1 (Always Warm)"]
        W2["Worker Pod 2 (Scaled on Demand)"]
        WN["Worker Pod N (Up to 5 max)"]

        HPA -->|Scale up / down| W1
        HPA -->|Scale up / down| W2
        HPA -->|Scale up / down| WN
    end
```

### Scaling Logic & Configuration

1. **Trigger Query**: KEDA polls PostgreSQL every 5 seconds executing:
   ```sql
   SELECT ceil(COUNT(*)::decimal / 16)
   FROM task_instance
   WHERE (state='running' OR state='queued')
     AND queue IN ('default')
   ```
2. **Capacity Ratio**: Celery workers run with concurrency `16`. When 16 tasks are active, 1 worker is required. When load bursts to 32 or 48 tasks, KEDA signals the HPA to instantly scale to 2 or 3 worker pods.
3. **Scaling Limits**:
   - `minReplicaCount: 1` — Keeps 1 warm worker pod running to eliminate cold-start latency for scheduled DAGs.
   - `maxReplicaCount: 5` — Safeguards cluster compute capacity while allowing 5x parallel throughput.
   - `cooldownPeriod: 30s` — Prevents rapid flapping after burst completion.

Inspect real-time autoscaler health with:
```bash
./ctl autoscaler
```

---

## Observability Stack — Prometheus & Grafana

Operational health is continuously monitored using an enterprise **Prometheus & Grafana observability pipeline**:

1. **StatsD Emission**: All Airflow containers (scheduler, worker, api-server, dag-processor, triggerer) emit fine-grained StatsD metrics over UDP to `airflow-statsd:9125`.
2. **Prometheus Metrics Bridge**: The `statsd-exporter` translates StatsD metrics into standard Prometheus metrics on port `9102`.
3. **Zero-Trust Network Policy**: A dedicated `allow-prometheus-scrape-statsd` NetworkPolicy permits pods in namespace `observability` to scrape metrics across namespace boundaries while preserving network isolation.
4. **Grafana Dashboards**: Grafana runs with Prometheus pre-configured as the default datasource and comes pre-loaded with an **Airflow Production Overview** dashboard.

### Key Metrics Monitored in Grafana

| Metric | Source | Purpose |
|:---|:---|:---|
| `airflow_scheduler_heartbeat` | Scheduler | Liveness & health of Airflow schedulers |
| `airflow_executor_open_slots` | Celery Executor | Available capacity in the Celery worker pool |
| `airflow_executor_queued_tasks` | Celery Broker | Backlog latency and pending task instances |
| `airflow_executor_running_tasks` | Celery Workers | Active parallel execution load |
| `airflow_ti_finish` (by state) | Task Instances | Success, failure, and retry rates |
| `airflow_dag_processing_total_parse_time` | DAG Processor | Detection of slow DAG parsing or parsing stalls |

Access the dashboard:
```bash
./ctl metrics
# Open https://grafana.local (or port-forward: kubectl port-forward svc/grafana 3000:3000 -n observability)
```

### Unified Alerting & Platform Notifications (Grafana + Prometheus)

Operational monitoring is paired with automated **Grafana Unified Alerting** routed to Gmail (`alerts@example.com`) via TLS/STARTTLS relay on `smtp.gmail.com:587`:

1. **Pre-Provisioned Contact Points**: `email-admin` contact point is loaded as code via `alerting.yaml` ConfigMap, referencing the cluster `grafana-smtp-secret`.
2. **Notification Policy**: Default root policy matches all alert groups (`AirflowAlertRules`), enforcing a 10s evaluation buffer, 30s group batching, and 1-hour alert deduplication/repeat intervals.
3. **Provisioned Alert Rules**:
   - **`AirflowSchedulerDown` (Severity: Critical)**: Continuously evaluates `sum(rate(airflow_scheduler_heartbeat[1m])) or vector(0) < 0.1`. If all schedulers cease heartbeat emission for > 1 minute, an alert email is dispatched.
   - **`AirflowDagImportErrors` (Severity: Warning)**: Evaluates `sum(airflow_dag_processing_import_errors) or vector(0) > 0`. Triggers when the DAG processor discovers syntax or import errors in the DAG folder.

#### Airflow DAG Failure Alerts vs. Grafana Platform Alerts

| Dimension | Airflow DAG Alerting (`./ctl test-alert`) | Grafana Platform Alerting (`./ctl test-grafana-alert`) |
|:---|:---|:---|
| **Primary Scope** | Pipeline & data task instance execution errors | Infrastructure & service health / cluster availability |
| **Alert Engine** | Airflow `SmtpNotifier` in DAG `default_args` | Grafana Unified Alerting + Prometheus queries |
| **Source Data** | Database task instance state (`FAILED`) | Time-series metrics from `statsd-exporter` (`9102`) |
| **Notification Channel**| Direct SMTP delivery via Celery worker pod | Alertmanager notification policy via Grafana pod |
| **Use Cases** | Downstream data missing, SQL syntax errors, API timeouts | Schedulers down, Celery queue backlog, broken DAG files |
| **Test Command** | `./ctl test-alert` | `./ctl test-grafana-alert` |

---

## RBAC Architecture — Owner-Based Dynamic Access Control

The RBAC system achieves **complete DAG isolation** between teams without
requiring DAG authors to hardcode any permissions. It uses a three-tier identity
chain.

### The Identity Chain: LDAP → Keycloak → Airflow

```mermaid
flowchart LR
    subgraph LDAP["OpenLDAP (Source of Truth)"]
        U1["uid=user_finance"]
        G1["cn=aid-finance-auth"]
        U1 -.->|memberOf| G1
    end

    subgraph KC["Keycloak (Identity Broker)"]
        FED["LDAP User Federation"]
        GM["Group Mapper"]
        FED -->|sync| GM
    end

    subgraph AF["Airflow (Policy Enforcement)"]
        RM["AUTH_ROLES_MAPPING<br/><i>webserver_config.py</i>"]
        DP["dag_policy()<br/><i>airflow_local_settings.py</i>"]
        DAG["finance_monthly_report<br/><i>owner: finance</i>"]
    end

    G1 -->|"OIDC groups claim"| GM
    GM -->|"groups: [aid-finance-auth]"| RM
    RM -->|"Airflow Role: aid-finance-auth"| AF
    DP -->|"access_control[aid-finance-auth]<br/>= {can_read, can_edit, can_delete}"| DAG
```

| Layer | Component | Responsibility |
|:---|:---|:---|
| **Directory** | OpenLDAP | Stores users and AD security groups (`aid-<keyword>-auth`) |
| **Identity Broker** | Keycloak | Federates LDAP users, issues OIDC tokens with `groups` claim |
| **Auth Gateway** | `webserver_config.py` | Maps OIDC `groups` claim to Airflow roles via `AUTH_ROLES_MAPPING` |
| **Policy Engine** | `airflow_local_settings.py` | `dag_policy()` extracts `owner` from DAG, builds `aid-<owner>-auth`, sets `access_control` |

### How It Works End-to-End

1. **LDAP defines the truth**: `user_finance` belongs to group `aid-finance-auth`
2. **Keycloak federates**: Syncs users/groups from LDAP, includes `groups` in OIDC tokens
3. **Airflow maps roles at login**: `AUTH_ROLES_MAPPING` converts `aid-finance-auth` → Airflow role `aid-finance-auth`
4. **DAG Processor applies policy**: `dag_policy()` reads `owner="finance"` from the DAG, constructs `aid-finance-auth`, grants `{can_read, can_edit, can_delete}`
5. **Result**: `user_finance` sees **only** `finance_monthly_report`. All other DAGs are invisible.

### DAG Authoring Convention

> [!IMPORTANT]
> DAG developers **never hardcode `access_control`** in DAG files.
> All permission binding is dynamic via the `owner` keyword.

The naming convention for AD groups is: **`aid-<keyword>-auth`**

```python
# dags/finance/finance_report.py
with DAG(
    dag_id="finance_monthly_report",
    default_args={"owner": "finance"},   # ← "finance" maps to "aid-finance-auth"
    tags=["finance", "reporting"],
    ...
):
```

| Owner keyword | AD Group (auto-derived) | Users with access |
|:---|:---|:---|
| `finance` | `aid-finance-auth` | `user_finance`, `alice` (admin) |
| `marketing` | `aid-marketing-auth` | `user_marketing`, `alice` (admin) |
| `logistics` | `aid-logistics-auth` | `user_logistics`, `alice` (admin) |
| `analytics` | `aid-analytics-auth` | `user_analytics`, `alice` (admin) |

---

## Secrets Management — HashiCorp Vault

Vault runs in **dev mode** as an external container, connected to the KinD cluster
via Kubernetes Auth method (zero-secret, ServiceAccount-based authentication).

```
secret/data/airflow/
├── variables/
│   ├── keycloak_admin_password
│   ├── keycloak_client_secret
│   ├── breakglass_password
│   └── alert_recipient
├── config/
│   ├── core/fernet_key
│   ├── webserver/secret_key
│   └── api/secret_key
└── connections/
    ├── postgres_default
    ├── smtp_default
    └── aws_default
```

Airflow accesses Vault via the `VaultBackend` secrets backend, configured in
`values.yaml` under `config.secrets`. Pods authenticate using their Kubernetes
ServiceAccount token — no static tokens or passwords are injected.

---

## Remote Logging — MinIO S3

Task execution logs are shipped to MinIO (S3-compatible object storage) via the
`apache-airflow-providers-amazon` provider. Configuration in `values.yaml`:

| Setting | Value |
|:---|:---|
| `remote_logging` | `True` |
| `remote_log_conn_id` | `aws_default` (points to MinIO) |
| `remote_base_log_folder` | `s3://airflow-logs` |
| MinIO endpoint | `http://s3.airflow.svc.cluster.local:9000` |

---

## Failure Alerting — Gmail SMTP

When a task fails, Airflow sends an email notification via Gmail SMTP (STARTTLS
on port 587). The alert includes the DAG name, task ID, attempt number, and a
link to the task log. Custom HTML/text templates are baked into the Docker image
at `/opt/airflow/config/email/`.

> [!NOTE]
> A 16-character Google App Password is required. The startup script prompts for
> it interactively or reads from the `GMAIL_APP_PASSWORD` environment variable.

---

## Prerequisites

| Tool | Version | Purpose |
|:---|:---|:---|
| [Docker](https://docs.docker.com/get-docker/) | ≥ 24.x | Container runtime for KinD + external services |
| [KinD](https://kind.sigs.k8s.io/) | ≥ 0.20 | Local Kubernetes clusters in Docker |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | ≥ 1.28 | Kubernetes CLI |
| [Helm](https://helm.sh/docs/intro/install/) | ≥ 3.14 | Kubernetes package manager |
| [Python 3](https://www.python.org/) | ≥ 3.10 | Used by `./ctl test-auth` and Vault seed scripts |
| [jq](https://jqlang.github.io/jq/) | ≥ 1.6 | JSON processing in LDAP sync commands |
| [curl](https://curl.se/) | any | Health checks in setup scripts |

---

## Quick Start

```bash
# 1. Clone the repository
git clone git@github.com:your-org/airflow-enterprise-lab.git
cd Learn_Airflow

# 2. One command to launch everything
./ctl start
# ↳ Creates KinD cluster
# ↳ Builds custom Airflow Docker image
# ↳ Starts OpenLDAP + phpLDAPadmin + Keycloak + PostgreSQL + Redis + Vault + MinIO
# ↳ Bridges all external services into the cluster via K8s Services/Endpoints
# ↳ Deploys Airflow via Helm chart
# ↳ Seeds AD group roles and base permissions into Airflow DB

# 3. Check everything is healthy
./ctl status

# 4. Open Airflow and log in with Keycloak SSO
#    → http://localhost:8080 → Click "Sign in with keycloak"

# 5. Tear down when done
./ctl stop
```

---

## Access Endpoints & Credentials

### Secure Ingress Endpoints (HTTPS / TLS)

| Service | Short Domain (`/etc/hosts`) | Instant Wildcard URL (Zero Config) | Protocol | Certificate |
|:---|:---|:---|:---|:---|
| **Airflow Web UI** | `https://airflow.local` | `https://airflow.172.18.0.2.nip.io` | HTTPS / HTTP/2 | `airflow-tls-secret` (CA-signed) |
| **Keycloak SSO** | `https://auth.local` | `https://auth.172.18.0.2.nip.io` | HTTPS / HTTP/2 | `keycloak-tls-secret` (CA-signed) |
| **Flower Monitor** | `https://flower.local` | `https://flower.172.18.0.2.nip.io` | HTTPS / HTTP/2 | `flower-tls-secret` (CA-signed) |
| **Grafana UI** | `https://grafana.local` | `https://grafana.172.18.0.2.nip.io` | HTTPS / HTTP/2 | `grafana-tls-secret` (CA-signed) |
| **Prometheus UI** | `https://prometheus.local` | `https://prometheus.172.18.0.2.nip.io` | HTTPS / HTTP/2 | `prometheus-tls-secret` (CA-signed) |
| **HashiCorp Vault** | `https://vault.local` | `https://vault.172.18.0.2.nip.io` | HTTPS / HTTP/2 | `vault-tls-secret` (CA-signed) |
| **MinIO Console** | `https://minio.local` | `https://minio.172.18.0.2.nip.io` | HTTPS / HTTP/2 | `minio-tls-secret` (CA-signed) |
| **phpLDAPadmin** | `https://ldap.local` | `https://ldap.172.18.0.2.nip.io` | HTTPS / HTTP/2 | `ldap-tls-secret` (CA-signed) |

### Direct Service & Legacy Fallback Endpoints

| Service | URL | Notes |
|:---|:---|:---|
| **Airflow Web UI (HTTP)** | [http://localhost:8080](http://localhost:8080) | NodePort 30080 fallback |
| **Keycloak Admin (HTTP)** | [http://localhost:8081](http://localhost:8081) | Realm: `airflow` |
| **phpLDAPadmin** | [http://localhost:8082](http://localhost:8082) | LDAP Web GUI |
| **HashiCorp Vault** | [http://localhost:8200](http://localhost:8200) | K8s ServiceAccount Auth |
| **MinIO Console** | [http://localhost:9001](http://localhost:9001) | S3 Object Browser |
| **Flower (HTTP)** | [http://localhost:5555](http://localhost:5555) | NodePort 30555 fallback |

### User Credentials

| User | Password | Group | DAG Access |
|:---|:---|:---|:---|
| `alice` | `Alice-lab-1` | `airflow-admins` | **All DAGs** (Super Admin) |
| `user_finance` | `Finance-lab-1` | `aid-finance-auth` | `finance_monthly_report` |
| `user_marketing` | `Marketing-lab-1` | `aid-marketing-auth` | `marketing_campaign_tracker` |
| `user_logistics` | `Logistics-lab-1` | `aid-logistics-auth` | `logistics_fleet_monitoring` |
| `user_analytics` | `Analytics-lab-1` | `aid-analytics-auth` | `analytics_daily_etl` |

### Admin Credentials

| Service | User | Password |
|:---|:---|:---|
| Keycloak Admin Console | `admin` | `admin` |
| phpLDAPadmin | `cn=admin,dc=example,dc=org` | `admin` |
| MinIO Console | `minioadmin` | `minioadmin` |
| Break-glass Airflow Admin | `breakglass` | Managed via K8s secret `airflow-breakglass-secret` |

> [!CAUTION]
> The break-glass admin bypasses SSO and authenticates directly against the
> Airflow database. Use it only for emergency recovery when Keycloak is unavailable.

---

## CLI Reference (`./ctl`)

The `ctl` script is a portable, dependency-free bash CLI that manages the entire
lab lifecycle.

| Command | Description |
|:---|:---|
| `./ctl start` | Create KinD cluster, build image, start all infra, deploy Airflow, Ingress, KEDA, and Observability |
| `./ctl stop` | Delete KinD cluster and stop all external Docker containers |
| `./ctl status` | Show pod health across all namespaces, external container status, and endpoints |
| `./ctl build` | Rebuild the custom Airflow Docker image |
| `./ctl autoscaler` | Inspect KEDA worker autoscaler targets, HPA status, and database queue depth |
| `./ctl metrics` | Check Prometheus & Grafana health, dashboard URLs, and port-forward helpers |
| `./ctl ingress` | View Ingress routing, cert-manager TLS certificates, and local `/etc/hosts` DNS setup |
| `./ctl hosts` | Automatically add or check `/etc/hosts` DNS records for all secure services |
| `./ctl test-alert` | Trigger the failure notification DAG and verify Airflow Gmail delivery |
| `./ctl test-grafana-alert` | Trigger Grafana Alerting notification test to Gmail (`alerts@example.com`) |
| `./ctl test-auth` | Test Keycloak OIDC token issuance for all team users |
| `./ctl logs <target>` | Tail logs for `worker`, `scheduler`, or `keycloak` |
| `./ctl vault status` | Check Vault container health |
| `./ctl vault ui` | Print Vault Web UI URL and root token |
| `./ctl vault start` | Start Vault and seed initial secrets |
| `./ctl ldap status` | Show OpenLDAP and phpLDAPadmin container status |
| `./ctl ldap ui` | Print phpLDAPadmin URL and login DN |
| `./ctl ldap list-users` | List all users in the LDAP directory |
| `./ctl ldap list-groups` | List all AD groups and their members |
| `./ctl ldap add-user` | Create a new LDAP user and add to an AD group |
| `./ctl ldap sync` | Trigger Keycloak full LDAP sync |

A `Makefile` wrapper is also available for common commands (`make start`,
`make stop`, `make status`, `make build`, `make test-alert`, `make test-auth`).

---

## Project Structure

```text
.
├── ctl                                  # Portable CLI — manages full lab lifecycle
├── Makefile                             # Make wrapper for CI/CD-friendly commands
├── Dockerfile                           # Multi-stage Airflow 3 image (slim base + LDAP/auth/statsd deps)
├── requirements.txt                     # Python deps: celery, fab, postgres, redis, smtp, ldap, vault, s3, statsd
├── values.yaml                          # Helm chart values — executor, secrets, SMTP, git-sync, metrics, resources
│
├── constraints/
│   └── constraints-3.12.txt             # Pinned pip constraints for deterministic Python 3.12 builds
│
├── config/
│   ├── airflow_local_settings.py        # dag_policy() — dynamic owner-based RBAC cluster policy
│   ├── webserver_config.py              # Flask-AppBuilder OAuth — Keycloak OIDC provider + role mapping
│   └── email/
│       ├── content.html                 # Jinja2 HTML template for failure alert emails
│       └── subject.txt                  # Jinja2 subject line template
│
├── dags/
│   ├── analytics/
│   │   └── analytics_etl.py             # Analytics ETL pipeline (owner: analytics)
│   ├── finance/
│   │   └── finance_report.py            # Finance monthly report (owner: finance)
│   ├── logistics/
│   │   └── logistics_delivery.py        # Logistics fleet monitoring (owner: logistics)
│   └── marketing/
│       └── marketing_campaign.py        # Marketing campaign tracker (owner: marketing)
│
├── k8s/
│   ├── kind-cluster.yaml                # KinD config — Ingress node-labels & port mappings (80, 443, 8080, 5555)
│   ├── ingress/
│   │   ├── cluster-issuer.yaml          # cert-manager Root CA & CA ClusterIssuer
│   │   └── airflow-ingress.yaml         # Ingress rules with automated TLS termination
│   ├── keda/
│   │   └── keda-scaledobject.yaml       # KEDA ScaledObject & TriggerAuthentication for Celery workers
│   ├── observability/
│   │   ├── prometheus.yaml              # Prometheus deployment, config, and cross-namespace network policy
│   │   └── grafana.yaml                 # Grafana deployment, datasources, and pre-baked Airflow dashboard
│   ├── keycloak/
│   │   ├── deployment.yaml              # Keycloak K8s Deployment + Service (NodePort 30081)
│   │   ├── service.yaml                 # Headless Service + Endpoints bridging external Keycloak
│   │   └── realm-airflow.json           # Pre-built realm export: clients, roles, mappers, users
│   ├── ldap/
│   │   ├── bootstrap.ldif               # LDAP seed data: OUs, users, AD security groups
│   │   └── service.yaml                 # Headless Service + Endpoints bridging external OpenLDAP
│   ├── postgres/
│   │   └── service.yaml                 # Headless Service + Endpoints bridging external PostgreSQL
│   ├── redis/
│   │   └── service.yaml                 # Headless Service + Endpoints bridging external Redis
│   ├── vault/
│   │   └── service.yaml                 # Headless Service + Endpoints bridging external Vault
│   └── s3/
│       └── service.yaml                 # Headless Service + Endpoints bridging external MinIO
│
├── scripts/
│   ├── start-local-k8s.sh               # Master orchestrator — KinD + image build + all infra + Helm + Ingress/KEDA/Obs
│   ├── stop-local-k8s.sh                # Cluster deletion + external container shutdown
│   ├── setup-ingress.sh                 # NGINX Ingress controller & cert-manager TLS provisioning
│   ├── setup-keda.sh                    # KEDA operator provisioning & worker autoscaler setup
│   ├── setup-observability.sh           # Prometheus & Grafana deployment & dashboard setup
│   ├── setup-ldap.sh                    # OpenLDAP + phpLDAPadmin provisioning + LDIF seeding
│   ├── setup-keycloak.sh                # Keycloak provisioning + realm import + K8s bridge
│   ├── setup-db-redis.sh                # PostgreSQL 16 + Redis 7 provisioning + K8s secrets
│   ├── setup-vault.sh                   # Vault provisioning + K8s Auth + secret seeding
│   └── setup-s3.sh                      # MinIO provisioning + K8s bridge
│
└── plugins/                             # (Reserved) Airflow plugin directory
```

---

## DAG Development Rules

> [!WARNING]
> These rules are enforced across the repository. Violating them will break
> the RBAC model or cause DAG parsing failures.

1. **No `@dag` or `@task` decorators** — Do not use the TaskFlow API. Always use
   explicit Operator classes (`PythonOperator`, `BashOperator`, etc.)
2. **Context manager syntax** — Define DAGs with `with DAG(...) as dag:`
3. **Explicit dependencies** — Chain tasks using bitshift operators (`task1 >> task2`)
4. **Owner keyword** — Set `default_args={"owner": "<keyword>"}` to match your
   team's AD group (`aid-<keyword>-auth`)
5. **No hardcoded `access_control`** — Permissions are applied dynamically by
   `dag_policy()` in the cluster policy
6. **Tags** — Use `tags=["<keyword>"]` for additional categorization (tags
   matching `aid-*-auth` or known keywords are also auto-mapped by the policy)

---

## Troubleshooting

<details>
<summary><strong>Pods stuck in CrashLoopBackOff</strong></summary>

Check logs for the failing pod:
```bash
kubectl logs -n airflow <pod-name> -c <container> --tail=100
```
Common causes:
- PostgreSQL or Redis not reachable (external container stopped)
- Vault secret sync failed (check `airflow-api-secret` exists)
- Docker image not loaded into KinD (`kind load docker-image ...`)
</details>

<details>
<summary><strong>Keycloak login redirects fail or loop</strong></summary>

Ensure Keycloak is healthy:
```bash
curl -s http://localhost:8081/realms/airflow/.well-known/openid-configuration | jq .issuer
```
The `KEYCLOAK_INTERNAL_URL` env var must resolve inside the cluster. Check the
`keycloak` headless Service and Endpoints:
```bash
kubectl get endpoints keycloak -n airflow
```
</details>

<details>
<summary><strong>User sees no DAGs after Keycloak login</strong></summary>

1. Verify the user's LDAP group membership: `./ctl ldap list-groups`
2. Verify Keycloak synced the groups: `./ctl test-auth`
3. Check that AD team roles exist in Airflow: `kubectl exec -n airflow deploy/airflow-scheduler -c scheduler -- airflow roles list`
4. Ensure the DAG has the correct `owner` in `default_args`
</details>

<details>
<summary><strong>Gmail alerts not sending</strong></summary>

1. Verify the SMTP secret exists:
   ```bash
   kubectl get secret airflow-smtp-secret -n airflow
   ```
2. Test with a real 16-char Google App Password (not the placeholder)
3. Check worker logs for SMTP errors: `./ctl logs worker`
</details>

<details>
<summary><strong>Vault connection errors in scheduler/worker logs</strong></summary>

1. Check Vault health: `./ctl vault status`
2. Verify Vault is on the KinD network: `docker network inspect kind`
3. Check the `vault` Service and Endpoints in Kubernetes:
   ```bash
   kubectl get endpoints vault -n airflow
   ```
</details>

---

## License

This project is for educational and lab purposes.
