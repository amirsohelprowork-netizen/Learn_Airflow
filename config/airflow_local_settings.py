"""Airflow Local Settings for Dynamic Keyword/Owner-Based RBAC.

Cluster policy automatically intercepts DAGs on parse and maps the owner keyword
to the matching AD group pattern: aid-<keyword>-auth.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from airflow.sdk import DAG

log = logging.getLogger(__name__)


def dag_policy(dag: DAG) -> None:
    """Dynamically applies RBAC based on DAG owner keyword.

    Pattern: aid-<keyword>-auth
    E.g. If dag has owner="finance", the AD group 'aid-finance-auth' gets full access.
    """
    if getattr(dag, "access_control", None) is None:
        dag.access_control = {}

    owner = getattr(dag, "default_args", {}).get("owner", getattr(dag, "owner", ""))
    tags = set(getattr(dag, "tags", []) or [])

    # If owner keyword is present, bind corresponding aid-<keyword>-auth role
    if owner:
        keyword = owner.strip().lower()
        target_role = f"aid-{keyword}-auth"
        dag.access_control[target_role] = {"can_read", "can_edit", "can_delete"}
        log.info(
            "Applied dynamic RBAC policy: role '%s' granted full control over DAG '%s' (owner: '%s')",
            target_role,
            dag.dag_id,
            owner,
        )

    # Support tags matching aid-*-auth or recognized keywords
    for tag in tags:
        tag_lower = tag.strip().lower()
        if tag_lower.startswith("aid-") and tag_lower.endswith("-auth"):
            dag.access_control[tag_lower] = {"can_read", "can_edit", "can_delete"}
        elif tag_lower in ["finance", "marketing", "logistics", "analytics"]:
            dag.access_control[f"aid-{tag_lower}-auth"] = {"can_read", "can_edit", "can_delete"}


__all__ = ["dag_policy"]
