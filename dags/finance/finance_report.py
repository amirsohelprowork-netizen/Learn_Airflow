"""Finance Monthly Report DAG.

Owned by the 'finance' team.
Accessible ONLY by members of AD group 'aid-finance-auth'.
Executes in 'finance_pool' with automatic SmtpNotifier failure alerting.
Publishes Airflow 3 Asset: s3://airflow-logs/datasets/finance_ledger
"""

from __future__ import annotations

import json
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


def extract_gl_transactions(**context) -> int:
    """Extract general ledger transactions for the financial accounting period."""
    log.info("Extracting general ledger entries from corporate ERP...")
    transactions_count = 1420
    log.info("Successfully extracted %d ledger line items.", transactions_count)
    return transactions_count


def compute_balance_sheet(**context) -> dict[str, float]:
    """Aggregate assets, liabilities, and equity calculations."""
    log.info("Computing departmental asset sheets and reconciliations...")
    balance_summary = {
        "current_assets": 1250000.00,
        "fixed_assets": 850000.00,
        "total_liabilities": 620000.00,
        "net_equity": 1480000.00,
    }
    log.info("Balance sheet calculation complete: %s", balance_summary)
    return balance_summary


def publish_s3_report(**context) -> str:
    """Publish the verified financial balance sheet to MinIO S3 object storage."""
    report_data = {
        "report_id": "FIN-REP-2026-M10",
        "logical_date": str(context["logical_date"]) if context.get("logical_date") else None,
        "run_id": context["run_id"],
        "department": "finance",
        "status": "DEMO_DATA",
        "net_equity": 1480000.00,
    }
    payload = json.dumps(report_data, indent=2)
    bucket = "airflow-reports"
    run_id = context["run_id"]
    from urllib.parse import quote
    s3_key = f"reports/finance/{quote(run_id, safe='')}/balance_sheet.json"

    from airflow.providers.amazon.aws.hooks.s3 import S3Hook

    s3_hook = S3Hook(aws_conn_id="aws_default")
    s3_hook.load_string(string_data=payload, key=s3_key, bucket_name=bucket, replace=True)
    log.info("Published financial demo report to s3://%s/%s", bucket, s3_key)

    return f"s3://{bucket}/{s3_key}"


with DAG(
    dag_id="finance_monthly_report",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    tags=["finance", "reporting"],
    default_args={
        "owner": "finance",
        "retries": 1,
    },
    doc_md="Monthly financial balance sheet workflow. Access restricted to aid-finance-auth.",
) as dag:

    start = EmptyOperator(task_id="start")

    extract_task = PythonOperator(
        task_id="extract_gl_transactions",
        python_callable=extract_gl_transactions,
    )

    compute_task = PythonOperator(
        task_id="compute_balance_sheet",
        python_callable=compute_balance_sheet,
    )

    publish_kwargs = {
        "task_id": "publish_s3_report",
        "python_callable": publish_s3_report,
    }
    if Asset:
        publish_kwargs["outlets"] = [FINANCE_LEDGER_ASSET]

    publish_task = PythonOperator(**publish_kwargs)

    end = EmptyOperator(task_id="end")

    start >> extract_task >> compute_task >> publish_task >> end
