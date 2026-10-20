"""Analytics Daily ETL Pipeline DAG.

Owned by the 'analytics' team.
Accessible ONLY by members of AD group 'aid-analytics-auth'.
"""

from __future__ import annotations

from datetime import datetime

from airflow.providers.standard.operators.python import PythonOperator
from airflow.sdk import DAG


def run_analytics_etl() -> None:
    print("Running aggregation pipeline for analytics data warehouse...")


with DAG(
    dag_id="analytics_daily_etl",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    tags=["analytics", "etl"],
    default_args={
        "owner": "analytics",
        "retries": 1,
    },
    doc_md="Data warehouse ETL ingestion jobs. Access restricted to aid-analytics-auth.",
) as dag:

    etl_task = PythonOperator(
        task_id="run_analytics_etl",
        python_callable=run_analytics_etl,
    )
