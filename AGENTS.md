# Repository Rules & Guidelines

## Airflow DAG Authoring Rules
- **No `@dag` or `@task` Decorators**: Do **NOT** use the TaskFlow API (`@dag` or `@task` decorators, including `@task.python`, `@task.bash`, etc.) for any DAGs in this repository.
- **Context Manager**: Always define DAGs using `with DAG(...) as dag:`.
- **Explicit Operators**: Always use explicit Operator classes (e.g., `PythonOperator`, `BashOperator`, `EmptyOperator`).
- **Dependencies**: Explicitly chain tasks using bitshift operators (`task1 >> task2`).
- **RBAC**: Do not hardcode `access_control` on DAGs; access control is dynamically applied via cluster policy (`config/airflow_local_settings.py`) using `tags` (e.g. `tags=["team-a"]`).
