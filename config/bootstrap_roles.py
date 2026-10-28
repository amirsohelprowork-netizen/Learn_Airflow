"""Idempotent role and pool seeding, executed only in a scheduler container."""
from airflow.providers.fab.auth_manager.models import Role, Permission, Action, Resource
from airflow.settings import Session
from airflow.models.pool import Pool

DEPARTMENTS = ('finance', 'marketing', 'logistics', 'analytics')
BASE_PERMISSIONS = {
    ('can_read', 'Website'), ('can_read', 'DAG Code'), ('can_read', 'DAG Runs'),
    ('can_create', 'DAG Runs'), ('can_edit', 'DAG Runs'), ('can_read', 'Task Instances'),
    ('can_edit', 'Task Instances'), ('can_read', 'Task Logs'), ('can_read', 'XComs'),
    ('can_read', 'Assets'), ('can_read', 'DAG Versions'), ('can_read', 'DAG Warnings'),
    ('menu_access', 'DAGs'), ('menu_access', 'Browse'), ('menu_access', 'DAG Runs'),
    ('menu_access', 'Task Instances'), ('menu_access', 'Assets'),
}

with Session() as session:
    for department in DEPARTMENTS:
        role_name = f'aid-{department}-auth'
        role = session.query(Role).filter(Role.name == role_name).one_or_none()
        if role is None:
            role = Role(name=role_name)
            session.add(role)
        for permission in session.query(Permission).join(Action).join(Resource).all():
            key = (permission.action.name, permission.resource.name)
            # Preserve only centrally approved base permissions and this team's DAG grants.
            if key in BASE_PERMISSIONS and permission not in role.permissions:
                role.permissions.append(permission)
            elif key not in BASE_PERMISSIONS and not permission.resource.name.startswith('DAG:'):
                if permission in role.permissions:
                    role.permissions.remove(permission)
        pool_name = f'{department}_pool'
        pool = session.query(Pool).filter(Pool.pool == pool_name).one_or_none()
        if pool is None:
            session.add(Pool(pool=pool_name, slots=2, description=f'{department} concurrency quota', include_deferred=False))
    session.commit()
print('Department roles and execution pools reconciled.')
