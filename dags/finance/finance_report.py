"""Finance Monthly Report DAG.

Owned by the 'finance' team.
Accessible ONLY by members of AD group 'aid-finance-auth'.
"""

from __future__ import annotations

from datetime import datetime

from airflow.providers.standard.operators.python import PythonOperator
from airflow.sdk import DAG


def generate_balance_sheet() -> None:
    print("Generating monthly balance sheet for finance...")


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

    generate_task = PythonOperator(
        task_id="generate_balance_sheet",
        python_callable=generate_balance_sheet,
    )
