"""Team A failure drill.

Intentional failure used to prove SMTP delivery to Gmail (alerts@example.com).
RBAC is managed centrally via DAG tags (tags=["team-a"]) through cluster policy
in config/airflow_local_settings.py — no hardcoded access_control is needed here!
Uses traditional PythonOperator (no @dag or @task decorators).
"""

from __future__ import annotations

from datetime import datetime

from airflow.providers.smtp.notifications.smtp import send_smtp_notification
from airflow.providers.standard.operators.python import PythonOperator
from airflow.sdk import DAG


def trigger_intentional_failure() -> None:
    """Raises an intentional exception to test failure alerting."""
    raise RuntimeError("Intentional failure drill for Gmail SMTP alert.")


# Failure alert sent directly to user's Gmail
failure_email_notifier = send_smtp_notification(
    from_email="alerts@example.com",
    to="alerts@example.com",
    subject="[Airflow Alert] {{ dag.dag_id }} - {{ ti.task_id }} FAILED",
    html_content="""
    <h3>Airflow Task Failure Alert</h3>
    <p><b>DAG:</b> {{ dag.dag_id }}</p>
    <p><b>Task:</b> {{ ti.task_id }}</p>
    <p><b>State:</b> {{ ti.state }}</p>
    <p><b>Execution Time:</b> {{ ti.end_date }}</p>
    <p><b>Error:</b> {{ exception }}</p>
    """,
)

with DAG(
    dag_id="team_a_notify_on_failure",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    max_active_runs=1,
    tags=["team-a", "notifications"],
    default_args={
        "owner": "team-a",
        "retries": 0,
        "on_failure_callback": [failure_email_notifier],
    },
    doc_md=(
        "Intentional failure to test Gmail SMTP alert delivery and tag-based RBAC. "
        "Triggering this DAG dispatches an alert email to alerts@example.com."
    ),
) as dag:

    fail_task = PythonOperator(
        task_id="fail_on_purpose",
        python_callable=trigger_intentional_failure,
    )
