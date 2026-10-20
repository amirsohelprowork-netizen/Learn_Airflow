"""Marketing Campaign Tracker DAG.

Owned by the 'marketing' team.
Accessible ONLY by members of AD group 'aid-marketing-auth'.
"""

from __future__ import annotations

from datetime import datetime

from airflow.providers.standard.operators.python import PythonOperator
from airflow.sdk import DAG


def track_conversions() -> None:
    print("Tracking multi-channel marketing campaign conversions...")


with DAG(
    dag_id="marketing_campaign_tracker",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    tags=["marketing", "campaigns"],
    default_args={
        "owner": "marketing",
        "retries": 1,
    },
    doc_md="Marketing campaign performance tracker. Access restricted to aid-marketing-auth.",
) as dag:

    track_task = PythonOperator(
        task_id="track_conversions",
        python_callable=track_conversions,
    )
