# Project Context & Session Handover: Airflow 3 + Keycloak Local Kubernetes Lab

> **Purpose**: This document provides complete context, architectural blueprints, configuration state, resolved issues, credentials, and development rules for resuming work seamlessly in a new conversation session.

---

## 1. Executive Summary & Objective

This repository contains a production-grade, local Kubernetes (**KinD**) implementation of **Apache Airflow 3.3.2** integrated with **Keycloak IAM (v26.0.7)** for Enterprise Single Sign-On (SSO) and **Owner-Based Dynamic Role-Based Access Control (RBAC)**.

### Primary Objectives Achieved:
1. **Dynamic Owner-Based RBAC**: Airflow DAGs automatically map their `owner` keyword (e.g., `default_args={"owner": "finance"}`) to Active Directory (AD) security groups following the pattern `aid-<keyword>-auth` (e.g., `aid-finance-auth`).
2. **Strict DAG Multi-Tenant Isolation**: Each department user has full control (read, edit, trigger, delete, view task logs) over their owned DAG, and **zero access/visibility** to any other department's DAGs.
3. **Modern Airflow 3 React UI Compatibility**: Fully resolved all Fast-API / Uvicorn frontend 403 Forbidden errors by establishing seeded operational base permissions without breaking DAG isolation.
4. **Keycloak OIDC Single Sign-On**: Resolved hybrid localhost browser redirects and Kubernetes internal backchannel token verification (`iss` issuer matching).
5. **Component Secret Synchronization**: Unified Fernet and Webserver/API secret keys across scheduler, api-server, and Celery workers to enable log streaming without token mismatches.

---

## 2. System Architecture & Topology

All core services run within the local KinD cluster (`airflow-local`) under the `airflow` namespace:

```
                                  [ User Browser ]
                                         │
             ┌───────────────────────────┴───────────────────────────┐
             │ http://localhost:8080                                 │ http://localhost:8081
             ▼                                                       ▼
  ┌─────────────────────────────────────┐               ┌─────────────────────────────────────┐
  │         Airflow Web / API           │               │            Keycloak IAM             │
  │     (FastAPI / Uvicorn / UI)        │               │       (Realm: 'airflow')            │
  │  NodePort 30080 -> Port 8080        │               │    NodePort 30081 -> Port 8080      │
  └──────────────────┬──────────────────┘               └──────────────────┬──────────────────┘
                     │                                                     │
                     │ OIDC Token & UserInfo Verification (Backchannel)    │
                     │ http://keycloak.airflow.svc.cluster.local:8080       │
                     └─────────────────────────────────────────────────────┘
                                         │
      ┌──────────────────────────────────┼──────────────────────────────────┐
      ▼                                  ▼                                  ▼
┌──────────────────┐           ┌──────────────────┐               ┌──────────────────┐
│ Airflow          │           │ Celery Worker    │               │ DAG Processor    │
│ Scheduler        │           │ (Workload Pods)  │               │ (Policy Engine)  │
└────────┬─────────┘           └────────┬─────────┘               └────────┬─────────┘
         │                              │                                  │
         └──────────────────────────────┼──────────────────────────────────┘
                                        ▼
                      ┌────────────────────────────────────┐
                      │ PostgreSQL 16 (Metadata Database)  │
                      │ Redis 7.2     (Celery Broker)      │
                      └────────────────────────────────────┘
```

### Port Mapping & Access Points:
| Service | Role | Local URL | In-Cluster Service |
| :--- | :--- | :--- | :--- |
| **Airflow Web UI** | React Frontend & API Server | [http://localhost:8080](http://localhost:8080) | `airflow-webserver:8080` / `airflow-api-server:8080` |
| **Keycloak IAM** | Identity Provider / SSO | [http://localhost:8081](http://localhost:8081) | `keycloak.airflow.svc.cluster.local:8080` |
| **PostgreSQL 16** | Metadata DB | Cluster Internal | `airflow-postgresql.airflow.svc.cluster.local:5432` |
| **Redis 7.2** | Celery Broker | Cluster Internal | `airflow-redis.airflow.svc.cluster.local:6379` |
| **Gmail Alerts** | Outbound Failure SMTP | Outbound | `smtp.gmail.com:587` (STARTTLS) |

---

## 3. Credentials & RBAC Access Matrix

### Airflow Web UI Logins (via Keycloak SSO):
To log in, visit [http://localhost:8080](http://localhost:8080) and click **"Sign in with keycloak"**.

| Username | Password | AD Group (`aid-<keyword>-auth`) | Owned DAG ID | Access Level |
| :--- | :--- | :--- | :--- | :--- |
| `alice` | `Alice-lab-1` | `airflow-admins` | **All DAGs** | Super Admin (full cluster control) |
| `user_finance` | `Finance-lab-1` | `aid-finance-auth` | `finance_monthly_report` | Owner (read, edit, trigger, delete) |
| `user_marketing` | `Marketing-lab-1` | `aid-marketing-auth` | `marketing_campaign_tracker` | Owner (read, edit, trigger, delete) |
| `user_logistics` | `Logistics-lab-1` | `aid-logistics-auth` | `logistics_fleet_monitoring` | Owner (read, edit, trigger, delete) |
| `user_analytics` | `Analytics-lab-1` | `aid-analytics-auth` | `analytics_daily_etl` | Owner (read, edit, trigger, delete) |

### Administrative Backdoors:
- **Break-glass Local DB Admin**: `breakglass` / `ChangeMeInSecret123!` (Direct Airflow database account, bypasses Keycloak).
- **Keycloak Admin Console**: `admin` / `admin` at [http://localhost:8081](http://localhost:8081).

---

## 4. Key Architectural Patterns & Implementations

### A. Dynamic Owner-Based RBAC (`config/airflow_local_settings.py`)
Rather than manually hardcoding `access_control` inside every DAG file, an Airflow Cluster Policy intercepts every DAG during parsing:
1. Extracts `owner = dag.default_args.get("owner")` or `dag.owner`.
2. Normalizes keyword to lowercase (e.g. `finance`).
3. Computes the target role: `f"aid-{keyword}-auth"`.
4. Injects permissions dynamically into `dag.access_control[target_role] = {"can_read", "can_edit", "can_delete"}`.
5. Also inspects DAG `tags` for any tag matching `aid-*-auth` or specific team keywords.

### B. Seeded Base Permissions for Airflow 3 React UI (`scripts/start-local-k8s.sh`)
In Airflow 3, the React frontend (`/ui/dags`) performs automated background queries for execution state. If a custom role lacks base permissions, the UI displays a red **403 Forbidden** banner.
During cluster startup, `start-local-k8s.sh` automatically seeds the following permissions to each `aid-*-auth` role without granting global DAG read rights:
- Resources: `Asset Aliases`, `Assets`, `Backfills`, `Cluster Activity`, `DAG Code`, `DAG Dependencies`, `DAG Runs`, `DAG Versions`, `DAG Warnings`, `HITL Detail`, `ImportError`, `Jobs`, `My Password`, `My Profile`, `Pools`, `Plugins`, `SLA Misses`, `Task Instances`, `Task Logs`, `Website`, `XComs`.
- Actions: `can_read`, `can_create`, `can_edit`, `can_delete` (scoped to their owned task instances/runs), and required `menu_access`.

### C. Keycloak Hostname & Backchannel Issuer Resolution (`k8s/keycloak/deployment.yaml`)
To solve OIDC `iss` issuer mismatches between host-browser port forwards (`http://localhost:8081`) and in-cluster communication (`http://keycloak.airflow.svc.cluster.local:8080`), Keycloak was configured with:
```yaml
- name: KC_HOSTNAME
  value: "http://localhost:8081"
- name: KC_HOSTNAME_BACKCHANNEL_DYNAMIC
  value: "true"
```
This forces Keycloak to issue all JWT tokens with `iss: http://localhost:8081/realms/airflow`, matching the Authlib client discovery configuration.

### D. Component Secret Key Synchronization (`values.yaml`)
Airflow 3 signs and verifies worker task log tokens using `webserverSecretKey` / `apiSecretKey`. To prevent signature verification failures when reading worker logs from the UI/API server, static keys are pinned:
```yaml
webserverSecretKey: "2SL0kSlBxSYcpJnwzhBCWFlGf0mxEao2"
apiSecretKey: "2SL0kSlBxSYcpJnwzhBCWFlGf0mxEao2"
```

---

## 5. Repository Authoring Rules & Guidelines

When authoring new DAGs or modifying code in this repository, you **MUST** follow these non-negotiable rules:

1. **NO TaskFlow API**:
   - **NEVER** use `@dag`, `@task`, `@task.python`, `@task.bash`, or any other TaskFlow decorators.
   - **ALWAYS** define DAGs using the standard context manager:
     ```python
     with DAG(
         dag_id="example_dag",
         default_args={"owner": "finance"},
         ...
     ) as dag:
     ```
   - **ALWAYS** instantiate explicit Operator classes: `PythonOperator`, `BashOperator`, `EmptyOperator`, `EmailOperator`, etc.
2. **Explicit Bitshift Chaining**:
   - Task dependencies must always be chained using bitshift operators: `task1 >> task2 >> task3`.
3. **No Hardcoded `access_control` in DAGs**:
   - Do not write `access_control={...}` inside DAG definitions. The cluster policy in `config/airflow_local_settings.py` applies permissions automatically based on `owner`.
4. **Shell Command Audit Logging**:
   - Every shell command executed must be prepended to the `## Entries` section in [`agent-command.md`](file:///workspace/Learn_Airflow/agent-command.md).

---

## 6. Project Directory Map

```
/workspace/Learn_Airflow/
├── ctl                              # Central bash management CLI (status, start, stop, test-auth, etc.)
├── AGENTS.md                        # Non-negotiable repository agent rules
├── PROJECT_CONTEXT.md               # [THIS FILE] Complete handover and architectural memory
├── README.md                        # User documentation and architectural overview
├── Dockerfile                       # Custom Airflow 3.3.2 image with Authlib & email support
├── Makefile                         # Helper targets (delegates to ./ctl)
├── values.yaml                      # Helm values for Apache Airflow 3.3.2 deployment
├── requirements.txt                 # Python dependencies for custom Airflow image
├── agent-command.md                 # Mandatory shell command execution audit log
├── config/
│   ├── airflow_local_settings.py    # Cluster policy for dynamic owner-to-role RBAC
│   └── webserver_config.py          # Flask-AppBuilder / Authlib Keycloak OIDC SSO config
├── scripts/
│   └── start-local-k8s.sh           # Fully automated KinD, Keycloak, Helm & RBAC seed script
├── k8s/
│   ├── kind-cluster.yaml            # KinD 2-node cluster config with NodePort mappings
│   ├── keycloak/
│   │   ├── deployment.yaml          # Keycloak 26.0.7 deployment with dynamic backchannel
│   │   ├── service.yaml             # Keycloak NodePort service (30081 -> 8080)
│   │   └── realm-airflow.json       # Keycloak realm with groups, users, and OIDC mappers
│   └── test/
│       └── test-runner-pod.yaml     # In-cluster debugging pod template
├── dags/
│   ├── finance/
│   │   └── finance_report.py        # Owner: 'finance' -> aid-finance-auth
│   ├── marketing/
│   │   └── marketing_campaign.py    # Owner: 'marketing' -> aid-marketing-auth
│   ├── logistics/
│   │   └── logistics_delivery.py    # Owner: 'logistics' -> aid-logistics-auth
│   ├── analytics/
│   │   └── analytics_etl.py         # Owner: 'analytics' -> aid-analytics-auth
│   └── team_a/
│       └── notify_on_failure.py     # Email notification failure test DAG
├── plugins/                         # [Empty placeholder directory]
└── logs/                            # [Empty placeholder directory]
```

---

## 7. Operational Runbook

### Starting the Lab:
```bash
./ctl start
```
*What this does automatically:*
1. Checks for Docker and prerequisites.
2. Builds `custom-airflow:3.3.2-lab` Docker image.
3. Provisions KinD cluster `airflow-local` with port forwards (`8080`, `8081`).
4. Loads custom image into KinD.
5. Deploys Keycloak, mounts `realm-airflow.json`, and waits for readiness.
6. Deploys Airflow 3.3.2 using Helm with `values.yaml`.
7. Automatically seeds AD team roles (`aid-*-auth`) and base execution permissions.

### Checking Cluster Status:
```bash
./ctl status
```

### Validating OIDC SSO Backchannel Token:
```bash
./ctl test-auth
```
*Verifies Keycloak returns a valid JWT access token and userinfo payload for `user_finance`.*

### Testing Outbound Email Failure Alerts:
```bash
./ctl test-alert
```
*Triggers `team_a_notify_on_failure` and checks for dispatch to `alerts@example.com`.*

### Viewing Component Logs:
```bash
./ctl logs worker       # Follow worker logs
./ctl logs scheduler    # Follow scheduler logs
./ctl logs keycloak     # Follow Keycloak logs
```

### Stopping / Tearing Down the Cluster:
```bash
./ctl stop
```

---

## 8. Current System State & Next Steps

- **Cluster State**: Fully operational KinD cluster (`airflow-local`) with 10 pods Running.
- **Git-Sync**: Enabled via `values.yaml` targeting `git@github.com:your-org/airflow-enterprise-lab.git` on branch `main` (subpath: `dags`) with a 30-second sync interval (`period: 30s` / `wait: 30`). Authentication managed via Kubernetes secret `airflow-ssh-secret`.
- **Keycloak & Auth**: All 6 accounts (`alice`, `breakglass`, `user_finance`, `user_marketing`, `user_logistics`, `user_analytics`) provisioned and verified in Keycloak.
- **Immediate Next Steps**:
  1. Continue developing or testing DAG pipelines.
  2. Any changes pushed to GitHub `origin/main` under `dags/` will now automatically sync to Airflow within 30 seconds.

