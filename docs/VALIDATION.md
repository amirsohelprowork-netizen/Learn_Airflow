# Local validation — 29 October 2026 (IST)

The hardened stack was built and exercised on this Linux x86_64 machine. The final tested Airflow image tag is `learn-airflow:3.3.2-865e016af0fc002a`.

| Check | Result |
| --- | --- |
| `./ctl ci` | Passed: Python compilation, every Bash script, isolated Terraform initialization/validation, pinned Helm lint/render checks, and all 17 runtime tests |
| `./ctl scan` | Passed: no fixable HIGH or CRITICAL findings in the final Airflow runtime image using the downloaded Trivy database |
| `./ctl smoke --run-dag` | Passed after a full stop/start: verified HTTPS, healthy Airflow components, protected API, DAG parsing, scoped Vault access, and successful finance execution |
| `./ctl test-auth` | Passed: authorization-code login/group claims for five LDAP personas; real Airflow login, scoped DAG listing, and cross-department direct API denial for all four departments |
| Asset scheduling | Three successful finance runs and three successful downstream analytics runs observed |
| Failure email drill | Expected failed DAG; corresponding task-failure email captured in local Mailpit |
| Grafana alert evaluation | Scheduler and import-error rules both `inactive`, health `ok`, with no evaluation error |
| Stop/start persistence | Same credentials reused; PostgreSQL data, S3 reports/logs, captured messages, Vault state and monitoring volumes retained |
| Final deployment | All Airflow and observability pods ready; worker autoscaler connected and healthy |
| Repository hygiene | Generated secrets, CA signing key, `.env`, and local Terraform state ignored; `git diff --check` passed |

Live testing also found and corrected issues beyond syntax checks: Airflow 3 permission normalization, missing logical dates on manual runs, an incorrect OIDC callback prefix, an incompatible KEDA database URL, migration/readiness ordering, worker execution API routing, local volume ownership, and Grafana alert queries that needed instant results.

Scope limits: the vulnerability gate above covers the Airflow runtime and filters to fixable high/critical findings. It does not certify the external service images. Terraform was validated but not applied as a second lifecycle owner over the shell-managed cluster. The optional Nexus setup received static validation, not a live integration test. No real workload capacity benchmark, hostile DAG-author isolation, hardware availability guarantee, or disaster recovery exercise is claimed. See [LOCAL_SETUP.md](LOCAL_SETUP.md) for the supported environment and limitations.
