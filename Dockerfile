# Slim base so every provider is declared in requirements.txt.
# Python 3.12 is pinned because Python 3.10 reaches end of life in October 2026.
ARG AIRFLOW_VERSION=3.3.2
ARG PYTHON_VERSION=3.12
FROM apache/airflow:slim-${AIRFLOW_VERSION}-python${PYTHON_VERSION}

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ARG AIRFLOW_VERSION
COPY --chown=airflow:0 constraints/constraints-3.12.txt /opt/airflow/constraints/constraints-3.12.txt
COPY --chown=airflow:0 requirements.txt /opt/airflow/requirements/requirements.txt

USER airflow
RUN pip install --no-cache-dir \
        --constraint /opt/airflow/constraints/constraints-3.12.txt \
        "apache-airflow==${AIRFLOW_VERSION}" \
        -r /opt/airflow/requirements/requirements.txt

COPY --chown=airflow:0 config/ /opt/airflow/config/
COPY --chown=airflow:0 config/webserver_config.py /opt/airflow/webserver_config.py

ENV PYTHONPATH="/opt/airflow/config:${PYTHONPATH}"

USER airflow



