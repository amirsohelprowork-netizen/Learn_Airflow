#!/usr/bin/env python3
"""Verify live local services; optionally run a finance DAG end to end."""
from __future__ import annotations

import argparse
import json
import ssl
import time
import urllib.error
import urllib.request
import uuid

from local_cluster import kube, run
from local_config import LOCAL


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-dag', action='store_true', help='Trigger and wait for a finance DAG run')
    args = parser.parse_args()
    context = ssl.create_default_context(cafile=str(LOCAL / 'tls/ca.crt'))
    for url in ('https://localhost/api/v2/monitor/health',
                'https://localhost:8443/realms/airflow/.well-known/openid-configuration',
                'https://localhost:8200/v1/sys/health', 'http://localhost:8025/api/v1/messages'):
        with urllib.request.urlopen(url, context=context, timeout=15) as response:
            if response.status != 200:
                raise RuntimeError(f'Unhealthy service: {url}')
            body = json.load(response)
        if url.endswith('/monitor/health'):
            for component in ('metadatabase', 'scheduler', 'dag_processor'):
                if body.get(component, {}).get('status') != 'healthy':
                    raise RuntimeError(f'Airflow component unhealthy: {component}')
        print(f'OK: {url}')
    discovery_url = 'https://localhost:8443/realms/airflow/.well-known/openid-configuration'
    with urllib.request.urlopen(discovery_url, context=context, timeout=15) as response:
        discovery = json.load(response)
    assert discovery['issuer'] == 'https://localhost:8443/realms/airflow'
    # A protected endpoint must not disclose DAGs without authentication.
    try:
        urllib.request.urlopen('https://localhost/api/v2/dags', context=context, timeout=15)
    except urllib.error.HTTPError as error:
        assert error.code in (401, 403), error.code
    else:
        raise RuntimeError('Unauthenticated API access was allowed')
    kube('exec', '-n', 'airflow', 'deploy/airflow-scheduler', '-c', 'scheduler', '--',
         'python3', '-c', '''
from airflow.dag_processing.dagbag import DagBag
bag=DagBag('/opt/airflow/dags')
assert not bag.import_errors, bag.import_errors
assert {'finance_monthly_report','analytics_daily_etl'} <= bag.dags.keys()
print('Live image DAG parsing passed')
''')
    # Ensure Airflow service-account credentials cannot retrieve bootstrap/signing keys.
    kube('exec', '-n', 'airflow', 'deploy/airflow-worker', '-c', 'worker', '--', 'python3', '-c', '''
import hvac
from pathlib import Path
client=hvac.Client(url='https://vault.airflow.svc.cluster.local:8200',verify='/opt/airflow/tls/ca.crt')
client.auth.kubernetes.login(role='airflow',jwt=Path('/var/run/secrets/kubernetes.io/serviceaccount/token').read_text())
client.secrets.kv.v2.read_secret_version(path='airflow/connections/warehouse_default',raise_on_deleted_version=True)
try:
    client.secrets.kv.v2.read_secret_version(path='airflow/config/api/secret_key',raise_on_deleted_version=True)
except hvac.exceptions.Forbidden:
    pass
else:
    raise RuntimeError('Runtime identity can read a platform signing key')
print('Runtime Vault scope verified')
''')
    print('OK: authentication required, DAGs parse, and runtime Vault access is scoped.')
    if args.run_dag:
        run_id = 'smoke__' + uuid.uuid4().hex
        prefix = ('exec', '-n', 'airflow', 'deploy/airflow-scheduler', '-c', 'scheduler', '--')
        kube(*prefix, 'airflow', 'dags', 'unpause', 'finance_monthly_report')
        kube(*prefix, 'airflow', 'dags', 'trigger', '--run-id', run_id, 'finance_monthly_report')
        print(f'Triggered {run_id}; waiting up to 5 minutes.', flush=True)
        deadline = time.monotonic() + 300
        while time.monotonic() < deadline:
            result = run('docker', 'exec', 'airflow-local-postgres', 'psql', '-U', 'platform', '-d', 'airflow',
                         '-tAc', f"SELECT state FROM dag_run WHERE dag_id='finance_monthly_report' AND run_id='{run_id}';").strip()
            state = result
            if state == 'success':
                print('OK: finance extraction, report upload and Asset publication completed.')
                break
            if state == 'failed':
                raise RuntimeError(f'Finance smoke run failed: {run_id}')
            time.sleep(2)
        else:
            raise TimeoutError(f'Finance smoke run did not finish: {run_id}')
    print('Local smoke checks passed.')


if __name__ == '__main__':
    main()
