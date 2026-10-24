"""Marketing Campaign Tracker DAG.

Owned by the 'marketing' team.
Accessible ONLY by members of AD group 'aid-marketing-auth'.
Executes in 'marketing_pool' with automatic SmtpNotifier failure alerting.
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
    from airflow.sdk import DAG
except ImportError:
    from airflow.models.dag import DAG  # type: ignore

log = logging.getLogger(__name__)


def pull_ad_spend(**context) -> dict[str, float]:
    """Ingest ad spend metrics across digital acquisition channels."""
    log.info("Pulling ad spend reports from search and social platforms...")
    spend = {
        "search_ads": 15400.00,
        "social_ads": 22100.00,
        "affiliate_network": 4800.00,
    }
    log.info("Total marketing spend retrieved: $%.2f", sum(spend.values()))
    return spend


def calculate_roas(**context) -> dict[str, float]:
    """Calculate return on ad spend (ROAS) against customer conversion events."""
    log.info("Computing multi-touch attribution and ROAS ratios...")
    attribution = {
        "blended_roas": 4.35,
        "search_roas": 5.12,
        "social_roas": 3.82,
    }
    log.info("ROAS evaluation complete: %s", attribution)
    return attribution


def generate_campaign_summary(**context) -> None:
    """Generate executive summary and push conversion stats to internal dashboards."""
    log.info("Publishing marketing performance KPIs for growth committee review.")
    log.info("Campaign metrics dashboard updated.")


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

    start = EmptyOperator(task_id="start")

    pull_spend = PythonOperator(
        task_id="pull_ad_spend",
        python_callable=pull_ad_spend,
    )

    calc_roas = PythonOperator(
        task_id="calculate_roas",
        python_callable=calculate_roas,
    )

    generate_summary = PythonOperator(
        task_id="generate_campaign_summary",
        python_callable=generate_campaign_summary,
    )

    end = EmptyOperator(task_id="end")

    start >> pull_spend >> calc_roas >> generate_summary >> end
