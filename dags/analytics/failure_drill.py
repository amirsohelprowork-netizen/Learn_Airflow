"""Failure Alerting Drill DAG.

Owned by the 'analytics' team.
Used by './ctl test-alert' to test real Airflow task failure alerting via SmtpNotifier.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta

try:
    from airflow.providers.standard.operators.empty import EmptyOperator
except ImportError:
    from airflow.operators.empty import EmptyOperator  # type: ignore

try:
    from airflow.providers.standard.operators.python import PythonOperator
except ImportError:
    from airflow.operators.python import PythonOperator  # type: ignore

try:
    from airflow.sdk import DAG
except ImportError:
    from airflow.models.dag import DAG  # type: ignore

log = logging.getLogger(__name__)


def trigger_simulated_failure(**context) -> None:
    """Raise a deliberate error to trigger on_failure_callback (SmtpNotifier)."""
    log.info("Executing simulated failure drill task on Celery worker...")
    raise RuntimeError("Simulated task failure to verify end-to-end Airflow SmtpNotifier alerting pipeline.")


with DAG(
    dag_id="failure_drill",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    tags=["analytics", "monitoring", "alerting"],
    default_args={
        "owner": "analytics",
        "retries": 1,
        "retry_delay": timedelta(seconds=5),
    },
    doc_md="Simulated task failure drill to verify SmtpNotifier email dispatch via Celery worker.",
) as dag:

    start = EmptyOperator(task_id="start")

    fail_task = PythonOperator(
        task_id="test_notification",
        python_callable=trigger_simulated_failure,
    )

    start >> fail_task
