#!/usr/bin/env python3
"""Exercise local authorization-code login and LDAP group claims (no password grant)."""
from __future__ import annotations

import hashlib
import base64
from html.parser import HTMLParser
import http.cookiejar
import json
import secrets
import ssl
import urllib.error
import urllib.parse
import urllib.request

from local_config import LOCAL


class LoginForm(HTMLParser):
    def __init__(self):
        super().__init__()
        self.action = None
        self.hidden = {}

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'form' and attrs.get('id') == 'kc-form-login':
            self.action = attrs['action']
        if tag == 'input' and attrs.get('type') == 'hidden' and attrs.get('name'):
            self.hidden[attrs['name']] = attrs.get('value', '')


class CaptureCallback(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if newurl.startswith('https://localhost/auth/oauth-authorized/keycloak'):
            return None
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def verify_oidc() -> None:
    credentials = json.loads((LOCAL / 'secrets.json').read_text())
    context = ssl.create_default_context(cafile=str(LOCAL / 'tls/ca.crt'))
    base = 'https://localhost:8443/realms/airflow/protocol/openid-connect'
    callback = 'https://localhost/auth/oauth-authorized/keycloak'
    personas = [('alice', 'ALICE_PASSWORD', 'airflow-admins')]
    personas += [(f'user_{d}', f'{d.upper()}_PASSWORD', f'aid-{d}-auth')
                 for d in ('finance', 'marketing', 'logistics', 'analytics')]
    for username, password_key, group in personas:
        opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=context),
                                             urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()), CaptureCallback())
        state = secrets.token_urlsafe(24)
        verifier = secrets.token_urlsafe(48)
        challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
        query = urllib.parse.urlencode({'client_id': 'airflow', 'response_type': 'code', 'redirect_uri': callback,
                                       'scope': 'openid email profile', 'state': state,
                                       'code_challenge': challenge, 'code_challenge_method': 'S256'})
        with opener.open(base + '/auth?' + query, timeout=20) as response:
            form = LoginForm()
            form.feed(response.read().decode())
        if not form.action:
            raise RuntimeError(f'No Keycloak login form for {username}')
        fields = form.hidden | {'username': username, 'password': credentials[password_key]}
        try:
            response = opener.open(form.action, data=urllib.parse.urlencode(fields).encode(), timeout=20)
        except urllib.error.HTTPError as error:
            if error.code not in (302, 303) or not error.headers.get('Location', '').startswith(callback):
                raise
            params = urllib.parse.parse_qs(urllib.parse.urlsplit(error.headers['Location']).query)
        else:
            response.close()
            raise RuntimeError(f'OIDC login did not authorize {username}')
        if params.get('state') != [state] or 'code' not in params:
            raise RuntimeError(f'Invalid authorization response for {username}')
        token_request = urllib.request.Request(base + '/token', data=urllib.parse.urlencode({
            'grant_type': 'authorization_code', 'code': params['code'][0], 'redirect_uri': callback,
            'client_id': 'airflow', 'client_secret': credentials['KEYCLOAK_CLIENT_SECRET'],
            'code_verifier': verifier}).encode())
        with opener.open(token_request, timeout=20) as response:
            token = json.load(response)['access_token']
        with opener.open(urllib.request.Request(base + '/userinfo', headers={'Authorization': 'Bearer ' + token}), timeout=20) as response:
            claims = json.load(response)
        if group not in claims.get('groups', []):
            raise RuntimeError(f'{username}: expected group {group}')
        team_groups = {g for g in claims.get('groups', []) if g.startswith('aid-')}
        if username != 'alice' and team_groups != {group}:
            raise RuntimeError(f'{username}: unexpected cross-department groups')
        print(f'OK: authorization-code login and expected groups for {username}')


def verify_airflow_rbac() -> None:
    credentials = json.loads((LOCAL / 'secrets.json').read_text())
    context = ssl.create_default_context(cafile=str(LOCAL / 'tls/ca.crt'))
    expected = {'finance': {'finance_monthly_report'}, 'marketing': {'marketing_campaign_tracker'},
                'logistics': {'logistics_fleet_monitoring'}, 'analytics': {'analytics_daily_etl', 'failure_drill'}}
    for department, allowed in expected.items():
        opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=context),
                                             urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
        with opener.open('https://localhost/auth/login/keycloak', timeout=30) as response:
            form = LoginForm()
            form.feed(response.read().decode())
        if not form.action:
            raise RuntimeError('Airflow did not initiate the expected OIDC login')
        fields = form.hidden | {'username': f'user_{department}', 'password': credentials[department.upper() + '_PASSWORD']}
        with opener.open(form.action, data=urllib.parse.urlencode(fields).encode(), timeout=30):
            pass
        with opener.open('https://localhost/api/v2/dags', timeout=30) as response:
            visible = {dag['dag_id'] for dag in json.load(response)['dags']}
        if visible != allowed:
            raise RuntimeError(f'{department}: DAG visibility does not match department ownership')
        forbidden = 'marketing_campaign_tracker' if department == 'finance' else 'finance_monthly_report'
        try:
            opener.open('https://localhost/api/v2/dags/' + forbidden, timeout=30)
        except urllib.error.HTTPError as error:
            if error.code not in (403, 404):
                raise
        else:
            raise RuntimeError(f'{department}: cross-department direct API access was allowed')
        print(f'OK: Airflow session, scoped DAG list and cross-department API denial for {department}')


if __name__ == '__main__':
    verify_oidc()
    verify_airflow_rbac()
