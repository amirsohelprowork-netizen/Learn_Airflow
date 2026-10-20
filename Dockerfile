# Slim base so every provider is declared in requirements.txt.
# Python 3.12 is pinned because Python 3.10 reaches end of life in October 2026.
ARG AIRFLOW_VERSION=3.3.2
ARG PYTHON_VERSION=3.12
FROM apache/airflow:slim-${AIRFLOW_VERSION}-python${PYTHON_VERSION}

# The slim image ships a compiler that the airflow user cannot execute.
# python-ldap has no wheel for this image, so allow gcc for the build,
# then remove the compiler.
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        gcc \
        libldap-2.5-0 \
        libldap-dev \
        libsasl2-2 \
        libsasl2-dev \
    && apt-mark manual curl libldap-2.5-0 libsasl2-2 \
    && chmod 755 /usr/bin/gcc /usr/bin/cc /usr/bin/x86_64-linux-gnu-gcc-12

ARG AIRFLOW_VERSION
COPY --chown=airflow:0 constraints/constraints-3.12.txt /opt/airflow/constraints/constraints-3.12.txt
COPY --chown=airflow:0 requirements.txt /opt/airflow/requirements/requirements.txt

USER airflow
RUN pip install --no-cache-dir \
        --constraint /opt/airflow/constraints/constraints-3.12.txt \
        "apache-airflow==${AIRFLOW_VERSION}" \
        -r /opt/airflow/requirements/requirements.txt

USER root
RUN apt-get purge -y --auto-remove gcc libldap-dev libsasl2-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /home/airflow/.cache/pip

COPY --chown=airflow:0 dags/ /opt/airflow/dags/
COPY --chown=airflow:0 config/ /opt/airflow/config/
COPY --chown=airflow:0 config/webserver_config.py /opt/airflow/webserver_config.py

ENV PYTHONPATH="/opt/airflow/config:${PYTHONPATH}"

USER airflow


