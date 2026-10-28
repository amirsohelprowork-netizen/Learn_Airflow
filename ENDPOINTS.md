# Local endpoints

See the [supported endpoint and credential table](docs/LOCAL_SETUP.md#local-endpoints).

- Airflow: https://localhost
- Keycloak: https://localhost:8443
- Captured email: http://localhost:8025
- Vault: https://localhost:8200

Credentials are generated on your machine: `./ctl credentials`. Trust `.local/tls/ca.crt` for HTTPS. Management listeners bind to loopback.
