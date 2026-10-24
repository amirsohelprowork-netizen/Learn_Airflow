"""Enterprise CI/CD Governance & Quality Gate Test Suite.

Validates:
1. Zero @dag or @task decorators via AST parsing (enforcing AGENTS.md and .cursor/rules).
2. No hardcoded access_control in dags/**/*.py.
3. Airflow DagBag parsing without import errors.
4. Cluster policies (dag_policy, task_policy) dynamically injecting RBAC and pools.
"""

from __future__ import annotations

import ast
import os
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DAGS_DIR = REPO_ROOT / "dags"
CONFIG_DIR = REPO_ROOT / "config"

# Ensure config is on sys.path to load airflow_local_settings
if str(CONFIG_DIR) not in sys.path:
    sys.path.insert(0, str(CONFIG_DIR))

VALID_DEPARTMENTS = {"finance", "marketing", "logistics", "analytics"}


class TestDAGGovernanceAST(unittest.TestCase):
    """AST-level static checks running independently of Airflow runtime."""

    def setUp(self):
        self.dag_files = [
            f for f in DAGS_DIR.glob("**/*.py")
            if not f.name.startswith("__") and not f.name.startswith(".")
        ]
        self.assertTrue(len(self.dag_files) > 0, f"No DAG files found under {DAGS_DIR}")

    def test_zero_taskflow_decorators(self):
        """Rule: Never use @dag or @task decorators (enforce explicit operators)."""
        prohibited_decorators = {"dag", "task", "task.python", "task.bash"}

        for dag_path in self.dag_files:
            content = dag_path.read_text(encoding="utf-8")
            tree = ast.parse(content, filename=str(dag_path))

            for node in ast.walk(tree):
                # Check for prohibited imports: from airflow.decorators import ...
                if isinstance(node, ast.ImportFrom) and node.module:
                    self.assertFalse(
                        node.module.startswith("airflow.decorators"),
                        f"Prohibited import 'airflow.decorators' in {dag_path.name}:L{node.lineno}",
                    )

                # Check for decorator usage on functions
                if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    for decorator in node.decorator_list:
                        dec_name = ""
                        if isinstance(decorator, ast.Name):
                            dec_name = decorator.id
                        elif isinstance(decorator, ast.Attribute):
                            dec_name = f"{getattr(decorator.value, 'id', '')}.{decorator.attr}"
                        elif isinstance(decorator, ast.Call):
                            if isinstance(decorator.func, ast.Name):
                                dec_name = decorator.func.id
                            elif isinstance(decorator.func, ast.Attribute):
                                dec_name = f"{getattr(decorator.func.value, 'id', '')}.{decorator.func.attr}"

                        self.assertNotIn(
                            dec_name.lower(),
                            prohibited_decorators,
                            f"Prohibited decorator '@{dec_name}' used on '{node.name}' in {dag_path.name}:L{node.lineno}",
                        )

    def test_no_hardcoded_access_control(self):
        """Rule: Never hardcode access_control; rely strictly on cluster policy."""
        for dag_path in self.dag_files:
            content = dag_path.read_text(encoding="utf-8")
            tree = ast.parse(content, filename=str(dag_path))

            for node in ast.walk(tree):
                if isinstance(node, ast.keyword) and node.arg == "access_control":
                    self.fail(
                        f"Hardcoded 'access_control' found in {dag_path.name}:L{node.lineno}. "
                        "RBAC access_control must be applied dynamically by cluster policy."
                    )

    def test_explicit_department_ownership(self):
        """Rule: Every DAG must define an owner matching VALID_DEPARTMENTS."""
        for dag_path in self.dag_files:
            content = dag_path.read_text(encoding="utf-8")
            has_valid_owner = any(
                f'"owner": "{dept}"' in content or f"'owner': '{dept}'" in content
                for dept in VALID_DEPARTMENTS
            )
            self.assertTrue(
                has_valid_owner,
                f"DAG file {dag_path.name} does not specify a valid department owner in {VALID_DEPARTMENTS}",
            )


class TestClusterPolicyEngine(unittest.TestCase):
    """Unit tests for dag_policy and task_policy in config/airflow_local_settings.py."""

    def test_dag_policy_rbac_and_least_privilege(self):
        """Verify dag_policy assigns aid-<owner>-auth with read/edit (no delete)."""
        import airflow_local_settings
        from airflow_local_settings import AirflowClusterPolicyViolation

        class MockDAG:
            def __init__(self, dag_id: str, owner: str):
                self.dag_id = dag_id
                self.owner = owner
                self.default_args = {"owner": owner}
                self.tags = [owner]
                self.access_control = None
                self.on_failure_callback = None

        # Test valid department
        dag = MockDAG("finance_monthly_report", "finance")
        airflow_local_settings.dag_policy(dag)

        self.assertIn("aid-finance-auth", dag.access_control)
        perms = dag.access_control["aid-finance-auth"]
        self.assertEqual(perms, {"can_read", "can_edit"})
        self.assertNotIn("can_delete", perms)
        self.assertIn("finance", dag.tags)
        self.assertIsNotNone(dag.on_failure_callback)

        # Test invalid department rejection
        invalid_dag = MockDAG("rogue_dag", "unauthorized_team")
        with self.assertRaises(AirflowClusterPolicyViolation):
            airflow_local_settings.dag_policy(invalid_dag)

    def test_task_policy_timeouts_and_pools(self):
        """Verify task_policy sets timeouts, retries, and department pools."""
        import airflow_local_settings

        class MockTask:
            def __init__(self, task_id: str, owner: str):
                self.task_id = task_id
                self.owner = owner
                self.pool = None
                self.execution_timeout = None
                self.retries = 0
                self.retry_delay = None
                self.on_failure_callback = None

        task = MockTask("compute_metrics", "analytics")
        airflow_local_settings.task_policy(task)

        self.assertEqual(task.pool, "analytics_pool")
        self.assertIsNotNone(task.execution_timeout)
        self.assertGreaterEqual(task.retries, 2)
        self.assertIsNotNone(task.retry_delay)
        self.assertIsNotNone(task.on_failure_callback)


class TestDagBagIntegration(unittest.TestCase):
    """Airflow DagBag integration test verifying zero parse errors across all DAGs."""

    def test_dagbag_import_errors(self):
        try:
            try:
                from airflow.dag_processing.dagbag import DagBag
                dagbag = DagBag(dag_folder=str(DAGS_DIR))
            except (ImportError, TypeError):
                from airflow.models.dagbag import DagBag  # type: ignore
                try:
                    dagbag = DagBag(dag_folder=str(DAGS_DIR), include_examples=False)
                except TypeError:
                    dagbag = DagBag(dag_folder=str(DAGS_DIR))

            self.assertEqual(
                len(dagbag.import_errors),
                0,
                f"DagBag import errors detected: {dagbag.import_errors}",
            )

            expected_dags = {
                "finance_monthly_report",
                "marketing_campaign_tracker",
                "logistics_fleet_monitoring",
                "analytics_daily_etl",
            }
            loaded_dags = set(dagbag.dags.keys())
            import airflow_local_settings

            for expected in expected_dags:
                self.assertIn(
                    expected,
                    loaded_dags,
                    f"Expected DAG '{expected}' was not loaded by DagBag.",
                )

                dag = dagbag.dags[expected]
                owner = (dag.default_args.get("owner") or "").strip().lower()
                self.assertIn(owner, VALID_DEPARTMENTS)

                # Verify dag_policy dynamically injects least-privilege RBAC
                airflow_local_settings.dag_policy(dag)
                self.assertIn(f"aid-{owner}-auth", dag.access_control)
                self.assertEqual(
                    dag.access_control[f"aid-{owner}-auth"],
                    {"can_read", "can_edit"},
                )
                self.assertNotIn("can_delete", dag.access_control[f"aid-{owner}-auth"])

                # Verify task_policy dynamically isolates pools, retries, and timeouts
                for task in dag.tasks:
                    airflow_local_settings.task_policy(task)
                    self.assertEqual(
                        task.pool,
                        f"{owner}_pool",
                        f"Task '{task.task_id}' in DAG '{expected}' was not assigned to '{owner}_pool'.",
                    )
                    self.assertIsNotNone(
                        task.execution_timeout,
                        f"Task '{task.task_id}' in DAG '{expected}' missing execution_timeout.",
                    )
                    self.assertGreaterEqual(
                        task.retries,
                        1,
                        f"Task '{task.task_id}' in DAG '{expected}' has invalid retries.",
                    )
                    self.assertIsNotNone(
                        task.on_failure_callback,
                        f"Task '{task.task_id}' in DAG '{expected}' missing on_failure_callback.",
                    )

        except ImportError as exc:
            # When running on host without Airflow runtime installed, DagBag test is delegated to container
            print(f"[NOTICE] Airflow runtime not installed in current Python env ({exc}). DagBag integration runs via './ctl test' in container.")


if __name__ == "__main__":
    unittest.main()
