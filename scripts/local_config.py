#!/usr/bin/env python3
"""Generate local-only secrets and release metadata without external dependencies."""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
LOCAL = ROOT / '.local'
DEPARTMENTS = ('finance', 'marketing', 'logistics', 'analytics')
SECRET_NAMES = (
    'POSTGRES_ADMIN_PASSWORD', 'POSTGRES_PASSWORD', 'WAREHOUSE_PASSWORD',
    'KEYCLOAK_DB_PASSWORD', 'REDIS_PASSWORD', 'KEYCLOAK_ADMIN_PASSWORD',
    'KEYCLOAK_CLIENT_SECRET', 'LDAP_ADMIN_PASSWORD', 'MINIO_PASSWORD',
    'NEXUS_ADMIN_PASSWORD', 'GRAFANA_ADMIN_PASSWORD', 'AIRFLOW_ADMIN_PASSWORD',
    'AIRFLOW_API_SECRET', 'AIRFLOW_JWT_SECRET', 'ALICE_PASSWORD',
    *(f'{d.upper()}_PASSWORD' for d in DEPARTMENTS),
)


def private_write(path: Path, content: str, mode: int = 0o600) -> None:
    fd, name = tempfile.mkstemp(prefix=path.name + '.', suffix='.tmp', dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(content)
        temporary.chmod(mode)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def release_tag(root: Path = ROOT) -> str:
    """Hash every build input, including file names; independent of git cleanliness."""
    digest = hashlib.sha256()
    paths = [root / '.dockerignore', root / 'Dockerfile', root / 'requirements.txt', root / 'requirements-security.txt']
    for folder in ('constraints', 'config', 'dags', 'tests', 'scripts'):
        paths.extend(p for p in (root / folder).rglob('*')
                     if p.is_file() and '__pycache__' not in p.parts and p.suffix != '.pyc')
    for path in sorted(p for p in paths if p.exists()):
        digest.update(str(path.relative_to(root)).encode() + b'\0' + path.read_bytes())
    return f'3.3.2-{digest.hexdigest()[:16]}'


def _initialize() -> dict[str, str]:
    LOCAL.mkdir(mode=0o700, exist_ok=True)
    LOCAL.chmod(0o700)
    path = LOCAL / 'secrets.json'
    if path.exists():
        credentials = json.loads(path.read_text())
        missing = set(SECRET_NAMES) | {'AIRFLOW_FERNET_KEY'}
        missing -= credentials.keys()
        if missing:
            raise RuntimeError(f'Incomplete secrets file; restore missing keys: {sorted(missing)}')
        # Shell exports below are deliberately limited to generated safe alphabets.
        if any(not value or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_=' for c in value)
               for value in credentials.values()):
            raise RuntimeError('Invalid local secret encoding')
    else:
        credentials = {name: secrets.token_hex(24) for name in SECRET_NAMES}
        credentials['AIRFLOW_FERNET_KEY'] = base64.urlsafe_b64encode(secrets.token_bytes(32)).decode()
        private_write(path, json.dumps(credentials, indent=2) + '\n')
    private_write(LOCAL / 'secrets.env', ''.join(f'export {k}={v}\n' for k, v in credentials.items()))
    render_identity(credentials)
    return credentials


def initialize() -> dict[str, str]:
    import fcntl
    LOCAL.mkdir(mode=0o700, exist_ok=True)
    with (LOCAL / 'init.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return _initialize()


def render_identity(credentials: dict[str, str]) -> None:
    realm = json.loads((ROOT / 'k8s/keycloak/realm-airflow.json').read_text())
    realm['clients'][0]['secret'] = credentials['KEYCLOAK_CLIENT_SECRET']
    provider = realm['components']['org.keycloak.storage.UserStorageProvider'][0]
    provider['config']['bindCredential'] = [credentials['LDAP_ADMIN_PASSWORD']]
    realm['users'][0]['credentials'] = [{'type': 'password', 'value': credentials['AIRFLOW_ADMIN_PASSWORD'], 'temporary': False}]
    private_write(LOCAL / 'realm-airflow.json', json.dumps(realm, indent=2) + '\n', 0o644)
    source = (ROOT / 'k8s/ldap/bootstrap.ldif').read_text()
    blocks = source.split('\n\n')
    for i, block in enumerate(blocks):
        if 'userPassword:' not in block:
            continue
        username = next(line[5:] for line in block.splitlines() if line.startswith('uid: '))
        name = 'ALICE_PASSWORD' if username == 'alice' else username.removeprefix('user_').upper() + '_PASSWORD'
        blocks[i] = '\n'.join('userPassword: ' + credentials[name] if line.startswith('userPassword:') else line
                              for line in block.splitlines())
    private_write(LOCAL / 'bootstrap.ldif', '\n\n'.join(blocks) + '\n')


def certificates() -> None:
    tls = LOCAL / 'tls'
    tls.mkdir(exist_ok=True)
    if (tls / 'server.crt').exists():
        subprocess.run(['openssl', 'x509', '-checkend', '86400', '-noout', '-in', str(tls / 'server.crt')],
                       check=True, stdout=subprocess.DEVNULL)
        return
    subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:3072', '-nodes', '-days', '3650',
                    '-keyout', str(tls / 'ca.key'), '-out', str(tls / 'ca.crt'), '-subj', '/CN=Airflow Local CA',
                    '-addext', 'basicConstraints=critical,CA:TRUE',
                    '-addext', 'keyUsage=critical,keyCertSign,cRLSign'], check=True, capture_output=True)
    subprocess.run(['openssl', 'req', '-new', '-newkey', 'rsa:3072', '-nodes', '-keyout', str(tls / 'server.key'),
                    '-out', str(tls / 'server.csr'), '-subj', '/CN=localhost'], check=True, capture_output=True)
    private_write(tls / 'extensions.cnf',
                  'subjectAltName=DNS:localhost,DNS:airflow.local,DNS:auth.local,DNS:vault.local,'
                  'DNS:keycloak.airflow.svc.cluster.local,DNS:vault.airflow.svc.cluster.local,IP:127.0.0.1\n'
                  'extendedKeyUsage=serverAuth\n')
    subprocess.run(['openssl', 'x509', '-req', '-in', str(tls / 'server.csr'), '-CA', str(tls / 'ca.crt'),
                    '-CAkey', str(tls / 'ca.key'), '-CAcreateserial', '-out', str(tls / 'server.crt'),
                    '-days', '365', '-extfile', str(tls / 'extensions.cnf')], check=True, capture_output=True)
    (tls / 'ca.key').chmod(0o600)
    # Container users need read access to explicitly mounted files. Parent .local is 0700.
    (tls / 'server.key').chmod(0o644)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('init', 'tag', 'credentials'))
    args = parser.parse_args()
    if args.command == 'tag':
        print(release_tag())
        return
    credentials = initialize()
    certificates()
    if args.command == 'credentials':
        print(json.dumps(credentials, indent=2))
    else:
        print('Local credentials ready in .local/secrets.json (preserved on restart).')


if __name__ == '__main__':
    main()
