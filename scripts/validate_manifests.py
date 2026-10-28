"""Check rendered behavior rather than only YAML syntax."""
import sys
from pathlib import Path
import yaml

root = Path(__file__).resolve().parent.parent
for path in (root / 'k8s').rglob('*.yaml'):
    list(yaml.safe_load_all(path.read_text()))
objects = [o for o in yaml.safe_load_all(Path(sys.argv[1]).read_text()) if o]
workers = next(o for o in objects if o['kind'] == 'Deployment' and o['metadata']['name'] == 'airflow-worker')
assert workers['spec']['template']['spec']['terminationGracePeriodSeconds'] >= 120
production = len(sys.argv) > 2 and sys.argv[2] == 'production'
if production:
    assert workers['spec']['replicas'] == 3
    assert not any(o['kind'] == 'ScaledObject' for o in objects)
    assert not any(o['kind'] in ('Deployment', 'StatefulSet') and
                   any(name in o['metadata']['name'] for name in ('postgresql', 'redis'))
                   for o in objects)
    for obj in objects:
        if obj['kind'] in ('Deployment', 'StatefulSet') and obj['metadata']['name'] != 'airflow-statsd':
            pod = obj['spec']['template']['spec']
            assert pod['topologySpreadConstraints'], obj['metadata']['name']
            for container in pod['containers']:
                if container['name'] != 'statsd-exporter':
                    assert '@sha256:' in container['image'], container['image']
    config = next(o for o in objects if o['kind'] == 'ConfigMap' and o['metadata']['name'] == 'airflow-config')
    assert 'https://airflow.example.com' in config['data']['airflow.cfg']
    assert 'airflow/prod/connections' in config['data']['airflow.cfg']
    for path in (root / 'deploy' / 'production').glob('*.yaml'):
        list(yaml.safe_load_all(path.read_text()))
else:
    scaler = next(o for o in objects if o['kind'] == 'ScaledObject')
    assert scaler['spec']['minReplicaCount'] == 1
    assert '/ 2)' in scaler['spec']['triggers'][0]['metadata']['query']
    assert scaler['spec']['triggers'][0]['metadata']['connectionFromEnv'] == 'AIRFLOW_CONN_AIRFLOW_DB'
flower = next(o for o in objects if o['kind'] == 'Deployment' and o['metadata']['name'] == 'airflow-flower')
flower_container = flower['spec']['template']['spec']['containers'][0]
auth = next(e for e in flower_container['env'] if e['name'] == 'AIRFLOW__CELERY__FLOWER_BASIC_AUTH')
assert auth['valueFrom']['secretKeyRef'] == {'name': 'airflow-flower-secret', 'key': 'basicAuth'}
assert next(o for o in objects if o['kind'] == 'Service' and o['metadata']['name'] == 'airflow-flower')['spec']['type'] == 'ClusterIP'
assert not any(o['kind'] == 'Ingress' and 'flower' in o['metadata']['name'] for o in objects)
assert not any(o['kind'] == 'Secret' and 'connection' in o.get('data', {}) for o in objects)
for obj in objects:
    if obj['kind'] != 'Deployment' or obj['metadata']['name'] == 'airflow-statsd':
        continue
    pod = obj['spec']['template']['spec']
    assert pod['securityContext']['runAsNonRoot']
    for container in pod['containers']:
        assert container['securityContext']['allowPrivilegeEscalation'] is False
        assert not any(v['name'].startswith('git-sync') for v in pod.get('volumes', []))

has_migration = any(o['kind'] == 'Job' and o['metadata']['name'] == 'airflow-run-airflow-migrations' for o in objects)
assert has_migration == production, 'Local migrations are explicit; production uses chart hooks'
if production:
    job = next(o for o in objects if o['kind'] == 'Job' and o['metadata']['name'] == 'airflow-run-airflow-migrations')
    assert job['metadata']['annotations']['helm.sh/hook'] == 'post-install,post-upgrade'
assert any('podSelector' in source for rule in next(o for o in objects if o['kind'] == 'NetworkPolicy' and o['metadata']['name'] == 'airflow-api-server-policy')['spec']['ingress'] for source in rule.get('from', [])), 'Workers need internal execution API access'
print(f'Rendered Airflow security, external secrets and {"production" if production else "local"} profile checks passed.')
