"""Bitable (Base) CLI commands.

Bitable is Feishu's database product, similar to Airtable.

Actions:
    list_tables     List all tables in a base
    list_fields     List all fields (columns) in a table
    list_records    List records in a table
    get_record      Get a single record
    create_record   Create a new record
    update_record   Update an existing record
    delete_record   Delete a record

Examples:
    service feishu bitable list_tables app_token=bascnXXX
    service feishu bitable list_fields app_token=bascnXXX table_id=tblXXX
    service feishu bitable list_records app_token=bascnXXX table_id=tblXXX page_size=50
    service feishu bitable get_record app_token=bascnXXX table_id=tblXXX record_id=recXXX
    service feishu bitable create_record app_token=bascnXXX table_id=tblXXX data='{"fields":{"Name":"Test"}}'
    service feishu bitable update_record app_token=bascnXXX table_id=tblXXX record_id=recXXX data='{"fields":{"Name":"Updated"}}'
    service feishu bitable delete_record app_token=bascnXXX table_id=tblXXX record_id=recXXX
"""

import json
from typing import Any

from ..plugins import (
    bitable_list_tables,
    bitable_list_fields,
    bitable_list_records,
    bitable_get_record,
)
from ..api import call_api, call_api_with_method


# Available actions with their descriptions
ACTIONS = {
    'list_tables': 'List all tables in a Bitable base',
    'list_fields': 'List all fields (columns) in a table',
    'list_records': 'List records in a table (supports filtering)',
    'get_record': 'Get a single record by ID',
    'create_record': 'Create a new record',
    'update_record': 'Update an existing record',
    'delete_record': 'Delete a record',
}


def get_actions() -> dict[str, str]:
    """Return available actions and their descriptions."""
    return ACTIONS


def run_action(action: str, params: dict[str, Any]) -> dict:
    """
    Execute a bitable action.

    Args:
        action: Action name (list_tables, list_records, etc.)
        params: Parameters for the action

    Returns:
        API response as dict

    Raises:
        ValueError: If required parameters are missing
    """
    if action == 'list_tables':
        return _list_tables(params)
    elif action == 'list_fields':
        return _list_fields(params)
    elif action == 'list_records':
        return _list_records(params)
    elif action == 'get_record':
        return _get_record(params)
    elif action == 'create_record':
        return _create_record(params)
    elif action == 'update_record':
        return _update_record(params)
    elif action == 'delete_record':
        return _delete_record(params)
    else:
        raise ValueError(f"Unknown action: {action}")


def _require_params(params: dict, *required: str) -> None:
    """Check that required parameters are present."""
    missing = [p for p in required if p not in params]
    if missing:
        raise ValueError(f"Missing required parameters: {', '.join(missing)}")


def _list_tables(params: dict) -> dict:
    """List all tables in a Bitable base."""
    _require_params(params, 'app_token')
    return bitable_list_tables(
        app_token=params['app_token'],
        page_size=params.get('page_size', 20),
        page_token=params.get('page_token'),
    )


def _list_fields(params: dict) -> dict:
    """List all fields in a table."""
    _require_params(params, 'app_token', 'table_id')
    return bitable_list_fields(
        app_token=params['app_token'],
        table_id=params['table_id'],
        page_size=params.get('page_size', 100),
        page_token=params.get('page_token'),
    )


def _list_records(params: dict) -> dict:
    """List records in a table."""
    _require_params(params, 'app_token', 'table_id')
    return bitable_list_records(
        app_token=params['app_token'],
        table_id=params['table_id'],
        page_size=params.get('page_size', 20),
        page_token=params.get('page_token'),
        view_id=params.get('view_id'),
        filter_expr=params.get('filter'),
    )


def _get_record(params: dict) -> dict:
    """Get a single record."""
    _require_params(params, 'app_token', 'table_id', 'record_id')
    return bitable_get_record(
        app_token=params['app_token'],
        table_id=params['table_id'],
        record_id=params['record_id'],
    )


def _create_record(params: dict) -> dict:
    """Create a new record."""
    _require_params(params, 'app_token', 'table_id', 'data')

    # Parse data if it's a string
    data = params['data']
    if isinstance(data, str):
        try:
            data = json.loads(data)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in data: {e}")

    return call_api(
        domain='bitable',
        method_path=f"bitable/v1/apps/{params['app_token']}/tables/{params['table_id']}/records",
        body=data,
    )


def _update_record(params: dict) -> dict:
    """Update an existing record."""
    _require_params(params, 'app_token', 'table_id', 'record_id', 'data')

    # Parse data if it's a string
    data = params['data']
    if isinstance(data, str):
        try:
            data = json.loads(data)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in data: {e}")

    return call_api_with_method(
        http_method='PUT',
        method_path=f"bitable/v1/apps/{params['app_token']}/tables/{params['table_id']}/records/{params['record_id']}",
        body=data,
    )


def _delete_record(params: dict) -> dict:
    """Delete a record."""
    _require_params(params, 'app_token', 'table_id', 'record_id')

    return call_api_with_method(
        http_method='DELETE',
        method_path=f"bitable/v1/apps/{params['app_token']}/tables/{params['table_id']}/records/{params['record_id']}",
    )
