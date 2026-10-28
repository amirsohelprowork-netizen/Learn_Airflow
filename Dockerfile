# Slim base so every provider is declared in requirements.txt.
# Python 3.12 is pinned because Python 3.10 reaches end of life in October 2026.
ARG AIRFLOW_VERSION=3.3.2
ARG PYTHON_VERSION=3.12
FROM apache/airflow:slim-${AIRFLOW_VERSION}-python${PYTHON_VERSION}@sha256:a54e7bd6c4d7a17e55cd14b0ead257877b8f8111680d2692cbdba2ff32bd3ff3

USER root
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && apt-get install -y --no-install-recommends curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN /usr/python/bin/python3.12 -m pip install --no-cache-dir --no-user "pip==26.2.2"

ARG AIRFLOW_VERSION
COPY --chown=airflow:0 constraints/constraints-3.12.txt /opt/airflow/constraints/constraints-3.12.txt
COPY --chown=airflow:0 requirements.txt /opt/airflow/requirements/requirements.txt

USER airflow
ARG PIP_INDEX_URL="https://pypi.org/simple"

RUN pip install --no-cache-dir \
        --index-url "${PIP_INDEX_URL}" \
        --constraint /opt/airflow/constraints/constraints-3.12.txt \
        "apache-airflow==${AIRFLOW_VERSION}" \
        -r /opt/airflow/requirements/requirements.txt

COPY --chown=airflow:0 requirements-security.txt /opt/airflow/requirements/requirements-security.txt
# Release constraints bootstrap compatibility; apply reviewed security fixes separately.
RUN pip install --no-cache-dir "apache-airflow==${AIRFLOW_VERSION}" \
        -r /opt/airflow/requirements/requirements-security.txt \
    && pip uninstall -y uv \
    && rm -rf /home/airflow/.local/share/uv/tools \
    && pip check

COPY --chown=airflow:0 config/ /opt/airflow/config/
COPY --chown=airflow:0 config/webserver_config.py /opt/airflow/webserver_config.py

COPY --chown=airflow:0 dags/ /opt/airflow/dags/
COPY --chown=airflow:0 tests/ /opt/airflow/tests/
COPY --chown=airflow:0 scripts/*.py /opt/airflow/scripts/

ENV PYTHONPATH="/opt/airflow/config:${PYTHONPATH}"

# Dependencies are installed at build time. Remove installers and their vendored
# copies from the final runtime instead of carrying vulnerable build tooling.
USER root
RUN rm -rf /usr/python/lib/python3.12/site-packages/pip \
        /usr/python/lib/python3.12/site-packages/pip-*.dist-info \
        /home/airflow/.local/lib/python3.12/site-packages/pip \
        /home/airflow/.local/lib/python3.12/site-packages/pip-*.dist-info \
        /usr/python/bin/pip* /home/airflow/.local/bin/pip*
USER airflow



