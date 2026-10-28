#!/usr/bin/env python3
"""Local bootstrap operations shared by the shell and Terraform entry points."""
from __future__ import annotations

import argparse
import json
import os
import ssl
import subprocess
import time
import urllib.error
import urllib.request

from local_config import LOCAL, ROOT, initialize, private_write, release_tag


def run(*args: str, data: str | None = None) -> str:
    return subprocess.run(args, input=data, text=True, check=True, stdout=subprocess.PIPE).stdout


def kube(*args: str, data: str | None = None) -> str:
    return run('kubectl', '--context', 'kind-airflow-local', *args, data=data)


def apply(objects: list[dict]) -> None:
    kube('apply', '-f', '-', data=json.dumps({'apiVersion': 'v1', 'kind': 'List', 'items': objects}))


def secret(name: str, namespace: str, values: dict, kind: str = 'Opaque') -> dict:
    return {'apiVersion': 'v1', 'kind': 'Secret', 'type': kind,
            'metadata': {'name': name, 'namespace': namespace}, 'stringData': values}


def cluster_secrets() -> None:
    c = initialize()
    for ns in ('airflow', 'observability', 'keda'):
        apply([{'apiVersion': 'v1', 'kind': 'Namespace', 'metadata': {'name': ns}}])
    apply([
        secret('airflow-metadata-secret', 'airflow', {'connection':
               f"postgresql://airflow:{c['POSTGRES_PASSWORD']}@postgres.airflow.svc.cluster.local:5432/airflow"}),
        secret('airflow-result-backend-secret', 'airflow', {'connection':
               f"db+postgresql://airflow:{c['POSTGRES_PASSWORD']}@postgres.airflow.svc.cluster.local:5432/airflow"}),
        secret('airflow-broker-secret', 'airflow', {'connection':
               f"redis://:{c['REDIS_PASSWORD']}@redis.airflow.svc.cluster.local:6379/0"}),
        secret('airflow-api-secret', 'airflow', {'api-secret-key': c['AIRFLOW_API_SECRET']}),
        secret('airflow-fernet-secret', 'airflow', {'fernet-key': c['AIRFLOW_FERNET_KEY']}),
        secret('airflow-jwt-secret', 'airflow', {'jwt-secret': c['AIRFLOW_JWT_SECRET']}),
        secret('airflow-runtime-secret', 'airflow', {'KEYCLOAK_CLIENT_SECRET': c['KEYCLOAK_CLIENT_SECRET']}),
        secret('grafana-admin-secret', 'observability', {'password': c['GRAFANA_ADMIN_PASSWORD']}),
        secret('airflow-ca', 'airflow', {'ca.crt': (LOCAL / 'tls/ca.crt').read_text()}),
        secret('airflow-local-tls', 'airflow', {'tls.crt': (LOCAL / 'tls/server.crt').read_text(),
                                             'tls.key': (LOCAL / 'tls/server.key').read_text()}, 'kubernetes.io/tls'),
    ])


def bridge() -> None:
    services = {'postgres': ('postgres', 5432), 'redis': ('redis', 6379), 'vault': ('vault', 8200),
                's3': ('minio', 9000), 'keycloak': ('keycloak', 8443), 'openldap': ('openldap', 389),
                'phpldapadmin': ('phpldapadmin', 80), 'mailpit': ('mailpit', 1025)}
    objects = []
    for service, (container, port) in services.items():
        info = json.loads(run('docker', 'inspect', f'airflow-local-{container}'))[0]
        ip = info['NetworkSettings']['Networks']['kind']['IPAddress']
        if not ip:
            raise RuntimeError(f'{container} is not running on the kind network')
        metadata = {'name': service, 'namespace': 'airflow'}
        objects.extend([
            {'apiVersion': 'v1', 'kind': 'Service', 'metadata': metadata,
             'spec': {'ports': [{'name': 'service', 'port': port, 'targetPort': port}]}},
            {'apiVersion': 'v1', 'kind': 'Endpoints', 'metadata': metadata,
             'subsets': [{'addresses': [{'ip': ip}], 'ports': [{'name': 'service', 'port': port}]}]},
        ])
    apply(objects)


def vault() -> None:
    c = initialize()
    context = ssl.create_default_context(cafile=str(LOCAL / 'tls/ca.crt'))
    token = ''

    def request(path: str, payload: dict | None = None, method: str | None = None) -> dict:
        req = urllib.request.Request('https://localhost:8200/v1/' + path,
                                     data=None if payload is None else json.dumps(payload).encode(),
                                     headers={'X-Vault-Token': token, 'Content-Type': 'application/json'}, method=method)
        with urllib.request.urlopen(req, context=context, timeout=10) as response:
            content = response.read()
            return json.loads(content) if content else {}

    for attempt in range(60):
        try:
            status = request('sys/init')
            break
        except (OSError, urllib.error.URLError):
            if attempt == 59:
                raise
            time.sleep(2)
    if not status['initialized']:
        bootstrap = request('sys/init', {'secret_shares': 1, 'secret_threshold': 1}, 'PUT')
        private_write(LOCAL / 'vault-init.json', json.dumps(bootstrap, indent=2) + '\n')
    elif not (LOCAL / 'vault-init.json').exists():
        raise RuntimeError('Vault is initialized but .local/vault-init.json is missing. Restore it; do not reset storage.')
    bootstrap = json.loads((LOCAL / 'vault-init.json').read_text())
    token = bootstrap['root_token']
    if request('sys/seal-status')['sealed']:
        request('sys/unseal', {'key': bootstrap['keys_base64'][0]}, 'PUT')
    # Unseal returns before the Raft leader has finished becoming active.
    for attempt in range(60):
        try:
            request('sys/health')
            break
        except urllib.error.HTTPError as error:
            if error.code not in (429, 500, 503) or attempt == 59:
                raise
            time.sleep(2)
    if 'secret/' not in request('sys/mounts'):
        request('sys/mounts/secret', {'type': 'kv', 'options': {'version': '2'}}, 'POST')
    if 'file/' not in request('sys/audit'):
        request('sys/audit/file', {'type': 'file', 'options': {'file_path': '/vault/file/audit.log'}}, 'PUT')
    if 'kubernetes/' not in request('sys/auth'):
        request('sys/auth/kubernetes', {'type': 'kubernetes'}, 'POST')

    apply([
        {'apiVersion': 'v1', 'kind': 'ServiceAccount', 'metadata': {'name': 'vault-reviewer', 'namespace': 'airflow'}},
        {'apiVersion': 'rbac.authorization.k8s.io/v1', 'kind': 'ClusterRoleBinding',
         'metadata': {'name': 'airflow-local-vault-reviewer'},
         'roleRef': {'apiGroup': 'rbac.authorization.k8s.io', 'kind': 'ClusterRole', 'name': 'system:auth-delegator'},
         'subjects': [{'kind': 'ServiceAccount', 'name': 'vault-reviewer', 'namespace': 'airflow'}]},
        {'apiVersion': 'v1', 'kind': 'Secret', 'type': 'kubernetes.io/service-account-token',
         'metadata': {'name': 'vault-reviewer-token', 'namespace': 'airflow',
                      'annotations': {'kubernetes.io/service-account.name': 'vault-reviewer'}}},
    ])
    import base64
    for attempt in range(30):
        data = json.loads(kube('get', 'secret', 'vault-reviewer-token', '-n', 'airflow', '-o', 'json')).get('data', {})
        if 'token' in data and 'ca.crt' in data:
            break
        time.sleep(1)
    else:
        raise RuntimeError('Kubernetes did not provision the Vault reviewer token')
    request('auth/kubernetes/config', {
        'kubernetes_host': 'https://airflow-local-control-plane:6443',
        'kubernetes_ca_cert': base64.b64decode(data['ca.crt']).decode(),
        'token_reviewer_jwt': base64.b64decode(data['token']).decode()}, 'POST')
    policy = '\n'.join(f'path "secret/data/airflow/connections/{name}" {{ capabilities = ["read"] }}'
                       for name in ('aws_default', 'smtp_default', 'warehouse_default'))
    request('sys/policies/acl/airflow-runtime', {'policy': policy}, 'PUT')
    accounts = ['airflow-worker', 'airflow-scheduler', 'airflow-dag-processor', 'airflow-triggerer',
                'airflow-api-server']
    request('auth/kubernetes/role/airflow', {'bound_service_account_names': accounts,
            'bound_service_account_namespaces': ['airflow'], 'token_policies': ['airflow-runtime'],
            'token_ttl': '1h', 'token_max_ttl': '4h'}, 'POST')
    connections = {
        'smtp_default': {'conn_type': 'smtp', 'host': 'mailpit.airflow.svc.cluster.local', 'port': 1025,
                         'extra': json.dumps({'disable_ssl': True, 'disable_tls': True,
                                              'from_email': 'airflow@local.test'})},
        'aws_default': {'conn_type': 'aws', 'login': 'airflow-local', 'password': c['MINIO_PASSWORD'],
                        'extra': json.dumps({'endpoint_url': 'http://s3.airflow.svc.cluster.local:9000',
                                             'region_name': 'us-east-1'})},
        'warehouse_default': {'conn_type': 'postgres', 'host': 'postgres.airflow.svc.cluster.local',
                              'port': 5432, 'login': 'warehouse', 'password': c['WAREHOUSE_PASSWORD'],
                              'schema': 'warehouse'},
    }
    for name, connection in connections.items():
        request('secret/data/airflow/connections/' + name, {'data': connection}, 'POST')
    print('Vault initialized, unsealed, audited, and configured with scoped Kubernetes authentication.')


def buckets() -> None:
    # boto3 is provided by the pinned Airflow runtime, not required on the host.
    c = initialize()
    script = '''import boto3, json, sys, time
c=json.load(sys.stdin)
s3=boto3.client('s3',endpoint_url='http://airflow-local-minio:9000',aws_access_key_id='airflow-local',aws_secret_access_key=c['MINIO_PASSWORD'],region_name='us-east-1')
for attempt in range(60):
    try:
        existing={b['Name'] for b in s3.list_buckets()['Buckets']}
        break
    except Exception:
        if attempt == 59: raise
        time.sleep(2)
for name in ('airflow-logs','airflow-reports'):
    if name not in existing: s3.create_bucket(Bucket=name)
    s3.put_bucket_versioning(Bucket=name,VersioningConfiguration={'Status':'Enabled'})
s3.put_bucket_lifecycle_configuration(Bucket='airflow-logs',LifecycleConfiguration={'Rules':[{'ID':'expire-local-logs','Status':'Enabled','Filter':{'Prefix':''},'Expiration':{'Days':30},'NoncurrentVersionExpiration':{'NoncurrentDays':7}}]})
'''
    run('docker', 'run', '--rm', '-i', '--network', 'kind', '--entrypoint', 'python3',
        f'learn-airflow:{os.environ.get("AIRFLOW_IMAGE_TAG") or release_tag()}', '-c', script, data=json.dumps(c))


def migrate() -> None:
    c = initialize()
    # Run the exact release image before Helm readiness waits. No hook deadlock or
    # immutable Job template on rapid repeated upgrades, and no credentials in argv.
    private_write(LOCAL / 'migration.env',
                  f"AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql://airflow:{c['POSTGRES_PASSWORD']}@airflow-local-postgres:5432/airflow\n"
                  "AIRFLOW__CORE__AUTH_MANAGER=airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager\n"
                  f"KEYCLOAK_CLIENT_SECRET={c['KEYCLOAK_CLIENT_SECRET']}\n")
    tag = os.environ.get('AIRFLOW_IMAGE_TAG') or release_tag()
    print(run('docker', 'run', '--rm', '--network', 'kind', '--env-file', str(LOCAL / 'migration.env'),
              f'learn-airflow:{tag}', 'airflow', 'db', 'migrate'))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('secrets', 'bridge', 'vault', 'buckets', 'migrate'))
    args = parser.parse_args()
    if args.command == 'vault':
        import fcntl
        with (LOCAL / 'vault-bootstrap.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            vault()
    else:
        {'secrets': cluster_secrets, 'bridge': bridge, 'buckets': buckets, 'migrate': migrate}[args.command]()


if __name__ == '__main__':
    main()
