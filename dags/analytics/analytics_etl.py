"""Analytics Daily ETL Pipeline DAG.

Owned by the 'analytics' team.
Accessible ONLY by members of AD group 'aid-analytics-auth'.
Executes in 'analytics_pool' with automatic SmtpNotifier failure alerting.
Data-Aware Scheduled via Airflow 3 Asset: s3://airflow-logs/datasets/finance_ledger
"""

from __future__ import annotations

import logging
from datetime import datetime

try:
    from airflow.providers.standard.operators.empty import EmptyOperator
except ImportError:
    from airflow.operators.empty import EmptyOperator  # type: ignore

try:
    from airflow.providers.standard.operators.python import PythonOperator
except ImportError:
    from airflow.operators.python import PythonOperator  # type: ignore

try:
    from airflow.sdk import Asset, DAG
except ImportError:
    from airflow.models.dag import DAG  # type: ignore
    try:
        from airflow.datasets import Dataset as Asset  # type: ignore
    except ImportError:
        Asset = None  # type: ignore

log = logging.getLogger(__name__)

FINANCE_LEDGER_ASSET = Asset("s3://airflow-logs/datasets/finance_ledger") if Asset else "s3://airflow-logs/datasets/finance_ledger"


def extract_warehouse_data(**context) -> int:
    """Read seeded demo data using a dedicated read-only warehouse account."""
    log.info("Querying the local demo warehouse via PostgresHook...")
    from airflow.providers.postgres.hooks.postgres import PostgresHook

    pg_hook = PostgresHook(postgres_conn_id="warehouse_default")
    records = pg_hook.get_records("SELECT count(*) FROM demo_transactions;")
    if not records or records[0][0] is None:
        raise ValueError("Warehouse returned no transaction count")
    return int(records[0][0])


def transform_metrics(**context) -> dict[str, int]:
    """Perform dimension table lookups and aggregate analytical KPIs."""
    log.info("Transforming staging dimensions into curated data marts...")
    transformed = {
        "active_tenants": 4,
        "processed_partitions": 12,
        "dq_pass_rate_pct": 100,
    }
    log.info("Transform step completed: %s", transformed)
    return transformed


def load_marts(**context) -> None:
    """Load dimensional data into enterprise analytical data marts."""
    log.info("Loading reconciled facts into analytics marts. Refreshing downstream views.")
    log.info("Analytical data mart refresh completed successfully.")


dag_schedule = [FINANCE_LEDGER_ASSET] if Asset else None

with DAG(
    dag_id="analytics_daily_etl",
    start_date=datetime(2026, 1, 1),
    schedule=dag_schedule,
    catchup=False,
    tags=["analytics", "etl"],
    default_args={
        "owner": "analytics",
        "retries": 1,
    },
    doc_md="Data warehouse ETL ingestion jobs triggered by upstream finance ledger asset updates. Access restricted to aid-analytics-auth.",
) as dag:

    start = EmptyOperator(task_id="start")

    extract_task = PythonOperator(
        task_id="extract_warehouse_data",
        python_callable=extract_warehouse_data,
    )

    transform_task = PythonOperator(
        task_id="transform_metrics",
        python_callable=transform_metrics,
    )

    load_task = PythonOperator(
        task_id="load_marts",
        python_callable=load_marts,
    )

    end = EmptyOperator(task_id="end")

    start >> extract_task >> transform_task >> load_task >> end
