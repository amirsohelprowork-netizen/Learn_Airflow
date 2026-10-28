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
scaler = next(o for o in objects if o['kind'] == 'ScaledObject')
assert scaler['spec']['minReplicaCount'] == 1
assert '/ 2)' in scaler['spec']['triggers'][0]['metadata']['query']
assert scaler['spec']['triggers'][0]['metadata']['connectionFromEnv'] == 'AIRFLOW_CONN_AIRFLOW_DB'
assert not any(o['kind'] == 'Secret' and 'connection' in o.get('data', {}) for o in objects)
for obj in objects:
    if obj['kind'] != 'Deployment' or obj['metadata']['name'] == 'airflow-statsd':
        continue
    pod = obj['spec']['template']['spec']
    assert pod['securityContext']['runAsNonRoot']
    for container in pod['containers']:
        assert container['securityContext']['allowPrivilegeEscalation'] is False
        assert not any(v['name'].startswith('git-sync') for v in pod.get('volumes', []))
print('Rendered Airflow security, external secrets, worker scaling and manifest checks passed.')

assert not any(o['kind'] == 'Job' and o['metadata']['name'] == 'airflow-run-airflow-migrations' for o in objects), 'Migrations are run explicitly before Helm'
assert any('podSelector' in source for rule in next(o for o in objects if o['kind'] == 'NetworkPolicy' and o['metadata']['name'] == 'airflow-api-server-policy')['spec']['ingress'] for source in rule.get('from', [])), 'Workers need internal execution API access'
