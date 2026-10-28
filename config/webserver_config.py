"""Flask-AppBuilder Webserver & OAuth Configuration for Airflow 3."""
import os
from flask_appbuilder.security.manager import AUTH_OAUTH

AUTH_TYPE = AUTH_OAUTH
AUTH_USER_REGISTRATION = True
AUTH_USER_REGISTRATION_ROLE = "Public"
AUTH_ROLES_SYNC_AT_LOGIN = True
PERMANENT_SESSION_LIFETIME = 1800
SESSION_COOKIE_SECURE = True
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = "Lax"

KEYCLOAK_INTERNAL_URL = os.environ.get("KEYCLOAK_INTERNAL_URL", "https://keycloak.airflow.svc.cluster.local:8443")

OAUTH_PROVIDERS = [
    {
        "name": "keycloak",
        "icon": "fa-key",
        "token_key": "access_token",
        "remote_app": {
            "client_id": "airflow",
            "client_secret": os.environ["KEYCLOAK_CLIENT_SECRET"],
            "server_metadata_url": f"{KEYCLOAK_INTERNAL_URL}/realms/airflow/.well-known/openid-configuration",
            "api_base_url": f"{KEYCLOAK_INTERNAL_URL}/realms/airflow/protocol/",
            "client_kwargs": {
                "scope": "openid email profile",
            },
        },
    }
]

# Map Keycloak realm roles and group names directly to Airflow roles
AUTH_ROLES_MAPPING = {
    "Admin": ["Admin"],
    "airflow-admins": ["Admin"],
    "aid-finance-auth": ["aid-finance-auth"],
    "aid-marketing-auth": ["aid-marketing-auth"],
    "aid-logistics-auth": ["aid-logistics-auth"],
    "aid-analytics-auth": ["aid-analytics-auth"],
}
