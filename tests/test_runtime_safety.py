"""Regression tests for failure propagation, RBAC and deterministic local releases."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'scripts'))
sys.path.insert(0, str(ROOT / 'config'))


class TestPolicyBoundaries(unittest.TestCase):
    def test_policy_removes_cross_department_grants(self):
        from airflow_local_settings import dag_policy
        class Dag:
            dag_id = 'finance_demo'
            default_args = {'owner': 'finance'}
            tags = []
            access_control = {'aid-marketing-auth': {'DAGs': {'can_read', 'can_delete'}}}
            on_failure_callback = None
        dag = Dag()
        dag_policy(dag)
        self.assertEqual(dag.access_control, {'aid-finance-auth': {'DAGs': {'can_read', 'can_edit'}}})


class TestLocalCredentials(unittest.TestCase):
    def test_secrets_persist_and_generated_files_are_private(self):
        import local_config
        with tempfile.TemporaryDirectory() as folder:
            local = Path(folder) / '.local'
            with patch.object(local_config, 'LOCAL', local), patch.object(local_config, 'render_identity'):
                first = local_config.initialize()
                second = local_config.initialize()
            self.assertEqual(first, second)
            self.assertNotEqual(first['POSTGRES_PASSWORD'], first['WAREHOUSE_PASSWORD'])
            self.assertEqual((local / 'secrets.json').stat().st_mode & 0o777, 0o600)
            self.assertEqual((local / 'secrets.env').stat().st_mode & 0o777, 0o600)
            import base64
            self.assertEqual(len(base64.urlsafe_b64decode(first['AIRFLOW_FERNET_KEY'])), 32)

    def test_adding_flower_preserves_existing_credentials(self):
        import local_config
        with tempfile.TemporaryDirectory() as folder:
            local = Path(folder) / '.local'
            with patch.object(local_config, 'LOCAL', local), patch.object(local_config, 'render_identity'):
                original = local_config.initialize()
                original.pop('FLOWER_PASSWORD')
                (local / 'secrets.json').write_text(json.dumps(original))
                updated = local_config.initialize()
                self.assertEqual({k: v for k, v in updated.items() if k != 'FLOWER_PASSWORD'}, original)
                self.assertTrue(updated['FLOWER_PASSWORD'])
                self.assertEqual(updated, local_config.initialize())

    def test_configuration_changes_change_release_tag(self):
        from local_config import release_tag
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'Dockerfile').write_text('FROM example')
            (root / 'requirements.txt').write_text('dependency==1')
            (root / 'config').mkdir()
            config = root / 'config/settings.py'
            config.write_text('VALUE=1')
            before = release_tag(root)
            config.write_text('VALUE=2')
            self.assertNotEqual(before, release_tag(root))


class TestDAGFailurePropagation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            import airflow
        except ImportError:
            if os.getenv('AIRFLOW_REQUIRE_RUNTIME') == '1':
                raise
            raise unittest.SkipTest('Run ./ctl test inside the Airflow runtime')

    def load(self, relative):
        spec = importlib.util.spec_from_file_location('dag_under_test', ROOT / relative)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_failed_upload_does_not_publish_success(self):
        finance = self.load('dags/finance/finance_report.py')
        with patch('airflow.providers.amazon.aws.hooks.s3.S3Hook.load_string', side_effect=OSError('storage offline')):
            with self.assertRaisesRegex(OSError, 'storage offline'):
                finance.publish_s3_report(run_id='manual__test', logical_date='2026-01-01')

    def test_report_keys_are_run_specific_and_retry_stable(self):
        finance = self.load('dags/finance/finance_report.py')
        with patch('airflow.providers.amazon.aws.hooks.s3.S3Hook.load_string') as upload:
            first = finance.publish_s3_report(run_id='manual__one', logical_date='2026-01-01')
            retry = finance.publish_s3_report(run_id='manual__one', logical_date='2026-01-01')
            second = finance.publish_s3_report(run_id='manual__two', logical_date='2026-01-01')
        self.assertEqual(first, retry)
        self.assertNotEqual(first, second)
        self.assertTrue(first.startswith('s3://airflow-reports/'))

    def test_manual_run_without_logical_date_publishes_report(self):
        finance = self.load('dags/finance/finance_report.py')
        with patch('airflow.providers.amazon.aws.hooks.s3.S3Hook.load_string') as upload:
            finance.publish_s3_report(run_id='manual__without_logical_date')
        payload = json.loads(upload.call_args.kwargs['string_data'])
        self.assertIsNone(payload['logical_date'])
        self.assertEqual(payload['run_id'], 'manual__without_logical_date')

    def test_database_failure_is_not_replaced_with_fabricated_data(self):
        analytics = self.load('dags/analytics/analytics_etl.py')
        with patch('airflow.providers.postgres.hooks.postgres.PostgresHook.get_records', side_effect=OSError('database offline')):
            with self.assertRaisesRegex(OSError, 'database offline'):
                analytics.extract_warehouse_data()

    def test_warehouse_query_uses_business_data(self):
        analytics = self.load('dags/analytics/analytics_etl.py')
        with patch('airflow.providers.postgres.hooks.postgres.PostgresHook') as hook:
            hook.return_value.get_records.return_value = [(4,)]
            self.assertEqual(analytics.extract_warehouse_data(), 4)
            hook.assert_called_once_with(postgres_conn_id='warehouse_default')
            hook.return_value.get_records.assert_called_once_with('SELECT count(*) FROM demo_transactions;')


class TestBootstrapContracts(unittest.TestCase):
    def test_database_uri_is_compatible_with_keda(self):
        import local_cluster
        from local_config import SECRET_NAMES
        credentials = {key: 'a' * 48 for key in SECRET_NAMES}
        credentials['AIRFLOW_FERNET_KEY'] = 'key'
        with tempfile.TemporaryDirectory() as folder:
            local = Path(folder)
            (local / 'tls').mkdir()
            for name in ('ca.crt', 'server.crt', 'server.key'):
                (local / 'tls' / name).write_text('test fixture')
            with patch.object(local_cluster, 'LOCAL', local), patch.object(local_cluster, 'initialize', return_value=credentials), patch.object(local_cluster, 'apply') as apply:
                local_cluster.cluster_secrets()
            objects = apply.call_args.args[0]
        metadata = next(o for o in objects if o['metadata']['name'] == 'airflow-metadata-secret')
        self.assertTrue(metadata['stringData']['connection'].startswith('postgresql://'))
        self.assertNotIn('psycopg2', metadata['stringData']['connection'])

    def test_bundle_excludes_local_credentials_and_state(self):
        import copy_repo_to_txt as bundle
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ('.env', 'local.tfstate', 'terraform.tfvars'):
                path = root / name
                path.write_text('private')
                self.assertTrue(bundle.should_ignore(path, root, root / 'bundle.txt', bundle.DEFAULT_IGNORED_DIRS, bundle.DEFAULT_IGNORED_FILES, set()))
