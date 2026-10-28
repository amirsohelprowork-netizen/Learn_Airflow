"""Enterprise Cluster Policy: Multi-Tenant RBAC, SLA Timeouts, Pools & Auto-Alerting."""
from __future__ import annotations

import logging
import os
from datetime import timedelta
from pathlib import Path
from typing import TYPE_CHECKING

try:
    from airflow.exceptions import AirflowClusterPolicyViolation
except ImportError:
    class AirflowClusterPolicyViolation(Exception):  # type: ignore
        """Fallback exception when Airflow is not installed in host Python env."""

if TYPE_CHECKING:
    from airflow.models.baseoperator import BaseOperator
    from airflow.sdk import DAG

log = logging.getLogger(__name__)

VALID_DEPARTMENTS = {"finance", "marketing", "logistics", "analytics"}

# Resolve email directory supporting both container path (/opt/airflow/config/email)
# and local filesystem path relative to this file.
EMAIL_DIR = Path("/opt/airflow/config/email")
if not EMAIL_DIR.exists():
    EMAIL_DIR = Path(__file__).resolve().parent / "email"

subject_template = (
    EMAIL_DIR.joinpath("subject.txt").read_text(encoding="utf-8").strip()
    if EMAIL_DIR.joinpath("subject.txt").exists()
    else "[Airflow] {{ ti.dag_id }} {{ ti.task_id }} {{ ti.state }}"
)
content_template = (
    EMAIL_DIR.joinpath("content.html").read_text(encoding="utf-8")
    if EMAIL_DIR.joinpath("content.html").exists()
    else "<p>Task {{ ti.task_id }} in DAG {{ ti.dag_id }} failed.</p>"
)

try:
    from airflow.providers.smtp.notifications.smtp import send_smtp_notification

    alert_recipient = os.getenv("AIRFLOW_ALERT_EMAIL", "alerts@example.com")
    DEFAULT_FAILURE_NOTIFIER = send_smtp_notification(
        from_email=f"Airflow Alert <{alert_recipient}>",
        to=alert_recipient,
        subject=subject_template,
        html_content=content_template,
    )
except ImportError:
    if os.getenv("AIRFLOW_REQUIRE_RUNTIME") == "1":
        raise

    def DEFAULT_FAILURE_NOTIFIER(context):  # type: ignore
        raise RuntimeError("SMTP provider is required for failure notifications")


def dag_policy(dag: DAG) -> None:
    """Enforce department ownership, least-privilege RBAC, and failure alerting."""
    owner = (
        getattr(dag, "default_args", {}).get("owner")
        or getattr(dag, "owner", "")
        or ""
    ).strip().lower()

    if owner not in VALID_DEPARTMENTS:
        raise AirflowClusterPolicyViolation(
            f"DAG '{dag.dag_id}' has invalid owner '{owner}'. "
            f"Enterprise policy requires owner in: {sorted(VALID_DEPARTMENTS)}"
        )

    # 1. Least-Privilege RBAC: Team gets read/edit; only Admin can delete DAGs
    target_role = f"aid-{owner}-auth"
    # Replace author-supplied grants, including stale grants from another team.
    dag.access_control = {target_role: {"DAGs": {"can_read", "can_edit"}}}

    # 2. Enforce tags for UI discoverability
    if getattr(dag, "tags", None) is None:
        dag.tags = []
    if owner not in dag.tags:
        dag.tags.append(owner)

    # 3. Automatically attach SmtpNotifier if no failure callback is set
    if not getattr(dag, "on_failure_callback", None):
        dag.on_failure_callback = [DEFAULT_FAILURE_NOTIFIER]


def task_policy(task: BaseOperator) -> None:
    """Enforce execution timeouts, retries, and department pool isolation on every task."""
    owner = (getattr(task, "owner", "") or "").strip().lower()

    # 1. Prevent hung tasks from locking Celery worker slots indefinitely
    if getattr(task, "execution_timeout", None) is None:
        task.execution_timeout = timedelta(hours=2)

    # 2. Enforce minimum retry resilience
    if not getattr(task, "retries", None) or task.retries < 1:
        task.retries = 2
    if getattr(task, "retry_delay", None) is None:
        task.retry_delay = timedelta(minutes=5)

    # 3. Route tasks to their dedicated department pool if left on default_pool
    pool = getattr(task, "pool", None)
    if owner in VALID_DEPARTMENTS and (not pool or pool == "default_pool"):
        task.pool = f"{owner}_pool"

    # 4. Attach failure email notification at task level if not defined
    if not getattr(task, "on_failure_callback", None):
        task.on_failure_callback = [DEFAULT_FAILURE_NOTIFIER]


__all__ = ["dag_policy", "task_policy"]
