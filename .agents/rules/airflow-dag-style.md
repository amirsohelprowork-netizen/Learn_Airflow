# Airflow DAG Authoring Rules

## 1. Strictly Prohibited: TaskFlow API Decorators
- **NEVER** use `@dag` or `@task` decorators (including `@task.python`, `@task.bash`, etc.) when creating or modifying any DAG in this project.
- **NEVER** import decorators from `airflow.decorators`.

## 2. Mandatory: Context Manager & Explicit Operators
- Always define DAGs using the standard context manager:
  ```python
  from datetime import datetime
  from airflow.sdk import DAG  # or from airflow import DAG

  with DAG(
      dag_id="example_dag",
      start_date=datetime(2026, 1, 1),
      schedule=None,
      catchup=False,
      tags=["finance", "reporting"],
      default_args={"owner": "finance"},
  ) as dag:
  ```
- Always instantiate explicit Operator classes:
  ```python
  from airflow.providers.standard.operators.python import PythonOperator
  from airflow.providers.standard.operators.bash import BashOperator

  def run_logic() -> None:
      ...

  task_one = PythonOperator(
      task_id="run_logic_task",
      python_callable=run_logic,
  )

  task_two = BashOperator(
      task_id="echo_task",
      bash_command="echo 'Done'",
  )

  task_one >> task_two
  ```

## 3. Dependencies & RBAC
- Explicitly chain tasks using bitshift operators: `task_one >> task_two`.
- **Do NOT hardcode `access_control`**: RBAC permissions (`aid-<owner>-auth`) and isolated department pools (`<owner>_pool`) are assigned automatically by cluster policy (`config/airflow_local_settings.py`) based on `default_args={"owner": "<department>"}` (`finance`, `marketing`, `logistics`, `analytics`).
