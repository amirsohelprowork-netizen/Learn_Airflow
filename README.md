# Apache Airflow 3 + Keycloak Kubernetes Lab

Enterprise-grade Apache Airflow 3.3.2 deployment running on local Kubernetes (**KinD**) using Helm (`values.yaml`), with **Keycloak OpenID Connect (OIDC)** Single Sign-On, **Tag-Based RBAC**, and real-time failure alerts sent directly to **`alerts@example.com`**.

> **Session Handover Note**: For comprehensive architectural notes, resolved issues, credentials, and full context for starting a new conversation, refer to [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md).

---

## Architecture Overview

All services run locally inside the KinD cluster (`airflow-local`), with zero external dependencies except outbound failure alerts to Gmail SMTP:

| Service | Role | Access / Port |
| --- | --- | --- |
| **Airflow Web UI & API** | Airflow 3 UI (FastAPI/Uvicorn) | [http://localhost:8080](http://localhost:8080) (NodePort `30080`) |
| **Keycloak IAM** | Identity Provider & OIDC RBAC | [http://localhost:8081](http://localhost:8081) (NodePort `30081`) |
| **Celery Worker** | Workload execution container | Kubernetes StatefulSet |
| **Airflow Scheduler** | Schedules tasks and triggers | Kubernetes Deployment |
| **DAG Processor** | Parses DAGs and applies cluster policies | Kubernetes Deployment |
| **PostgreSQL 16** | Airflow metadata database | Embedded StatefulSet |
| **Redis 7.2** | Celery message broker | Embedded StatefulSet |
| **Gmail SMTP** | Outbound failure alerts via STARTTLS | External `smtp.gmail.com:587` |

---

## Management CLI (`./ctl`)

A single, dependency-free control script manages the entire environment:

```bash
# Check cluster status, access URLs, and test credentials
./ctl status

# Start KinD cluster, deploy Keycloak & Airflow
./ctl start

# Trigger test DAG and verify Gmail alert delivery
./ctl test-alert

# Test Keycloak token issuance and UserInfo claims
./ctl test-auth

# Follow component logs (worker, scheduler, or keycloak)
./ctl logs worker

# Tear down the local KinD cluster
./ctl stop
```

---

## Logins & AD Group Users (Owner-Based RBAC)

Access the Airflow Web UI at **[http://localhost:8080](http://localhost:8080)** and click **"Sign in with keycloak"**:

| Username | Password | AD Group (Pattern: `aid-<keyword>-auth`) | Accessible DAGs | Access Level |
| :--- | :--- | :--- | :--- | :--- |
| `alice` | `Alice-lab-1` | `airflow-admins` | **All DAGs** | Super Admin (full cluster control) |
| `user_finance` | `Finance-lab-1` | `aid-finance-auth` | **`finance_monthly_report`** | Full Owner (read, edit, trigger, delete) |
| `user_marketing` | `Marketing-lab-1` | `aid-marketing-auth` | **`marketing_campaign_tracker`** | Full Owner (read, edit, trigger, delete) |
| `user_logistics` | `Logistics-lab-1` | `aid-logistics-auth` | **`logistics_fleet_monitoring`** | Full Owner (read, edit, trigger, delete) |
| `user_analytics` | `Analytics-lab-1` | `aid-analytics-auth` | **`analytics_daily_etl`** | Full Owner (read, edit, trigger, delete) |

> [!NOTE]
> **Complete DAG Isolation**: Non-owners have **zero access** to unowned DAGs (the DAG does not even appear in their Airflow UI). Only the owner group and `alice` (Admin) can see and manage a DAG.

### Keycloak Administration
- **URL**: [http://localhost:8081](http://localhost:8081)
- **User**: `admin` | **Pass**: `admin`
- **Realm**: `airflow`

### Emergency Break-glass Admin
Local database superuser: `breakglass` / `ChangeMeInSecret123!`

---

## Keyword / Owner-Based RBAC Architecture

DAG developers **never hardcode permissions** inside DAG files.

1. **AD Group Nomenclature Pattern**:
   All team AD groups follow the standard pattern:
   `aid-<keyword>-auth` (e.g. `aid-finance-auth`, `aid-marketing-auth`).

2. **Developer writes clean code** with standard `owner`:
   ```python
   # dags/finance/finance_report.py
   with DAG(
       dag_id="finance_monthly_report",
       default_args={"owner": "finance"},   # <-- "finance" matches "aid-finance-auth"
       tags=["finance"],
       ...
   ):
   ```
3. **Cluster Policy dynamically binds access** (`config/airflow_local_settings.py`):
   When the DAG Processor parses the file, it extracts `owner="finance"`, builds the target role `aid-finance-auth`, and grants:
   `can_read`, `can_edit`, `can_delete`.
4. **Keycloak matches the user**:
   When `user_finance` logs in, Keycloak provides `groups: ["aid-finance-auth"]`, granting full access to `finance_monthly_report` and zero access to any other DAGs!

---

## Project Structure

```text
.
├── ctl                         # Portable management CLI (./ctl status, start, test-alert, etc.)
├── Makefile                    # Makefile wrapper for standard CI/CD workflows
├── Dockerfile                  # Airflow 3 image (baked-in dependencies, DAGs, email templates)
├── requirements.txt            # Python dependencies (fab, smtp, celery, ldap, authlib)
├── values.yaml                 # Primary Helm chart values for Kubernetes (includes airflowLocalSettings)
├── constraints/
│   └── constraints-3.12.txt    # Pinned pip constraints for Python 3.12
├── dags/
│   ├── analytics/
│   │   └── analytics_etl.py    # Analytics DAG (owned by 'analytics' -> aid-analytics-auth)
│   ├── finance/
│   │   └── finance_report.py   # Finance DAG (owned by 'finance' -> aid-finance-auth)
│   ├── logistics/
│   │   └── logistics_delivery.py# Logistics DAG (owned by 'logistics' -> aid-logistics-auth)
│   ├── marketing/
│   │   └── marketing_campaign.py# Marketing DAG (owned by 'marketing' -> aid-marketing-auth)
│   └── team_a/
│       └── notify_on_failure.py# Failure alert drill DAG for Gmail alerts
├── config/
│   ├── airflow_local_settings.py # Central cluster policy for Tag/Owner-based RBAC
│   ├── webserver_config.py     # Flask-AppBuilder OAuth / Keycloak OIDC integration
│   └── email/                  # Custom HTML & text templates for email alerts
│       ├── content.html
│       └── subject.txt
├── k8s/
│   ├── kind-cluster.yaml       # KinD config (port mappings: 8080 Airflow, 8081 Keycloak)
│   └── keycloak/
│       ├── deployment.yaml     # Keycloak Kubernetes Deployment & Service
│       └── realm-airflow.json  # Formatted Keycloak realm, clients, roles, and users
├── scripts/
│   ├── start-local-k8s.sh      # Automated startup & deployment script
│   └── stop-local-k8s.sh       # Clean cluster deletion script
└── README.md                   # Project documentation
```
