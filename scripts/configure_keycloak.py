#!/usr/bin/env python3
"""Reconcile the local OIDC client after first import and subsequent restarts."""
import json
import ssl
import urllib.parse
import urllib.request

from local_config import LOCAL


def main():
    credentials = json.loads((LOCAL / 'secrets.json').read_text())
    context = ssl.create_default_context(cafile=str(LOCAL / 'tls/ca.crt'))
    base = 'https://localhost:8443'
    data = urllib.parse.urlencode({'client_id': 'admin-cli', 'grant_type': 'password', 'username': 'admin',
                                  'password': credentials['KEYCLOAK_ADMIN_PASSWORD']}).encode()
    with urllib.request.urlopen(base + '/realms/master/protocol/openid-connect/token', data=data, context=context, timeout=20) as response:
        token = json.load(response)['access_token']
    headers = {'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'}
    req = urllib.request.Request(base + '/admin/realms/airflow/clients?clientId=airflow', headers=headers)
    with urllib.request.urlopen(req, context=context, timeout=20) as response:
        clients = json.load(response)
    if len(clients) != 1:
        raise RuntimeError('Expected exactly one Airflow OIDC client')
    client = clients[0]
    client.update({'secret': credentials['KEYCLOAK_CLIENT_SECRET'], 'directAccessGrantsEnabled': False,
                   'redirectUris': ['https://localhost/auth/oauth-authorized/keycloak',
                                    'https://airflow.local/auth/oauth-authorized/keycloak'],
                   'webOrigins': ['https://localhost', 'https://airflow.local']})
    req = urllib.request.Request(base + '/admin/realms/airflow/clients/' + client['id'],
                                 data=json.dumps(client).encode(), headers=headers, method='PUT')
    with urllib.request.urlopen(req, context=context, timeout=20):
        pass
    print('OIDC callback allowlist and client credentials reconciled.')


if __name__ == '__main__':
    main()
