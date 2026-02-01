"""Calendar CLI commands.

Manage calendars and events in Feishu Calendar.

Actions:
    list_calendars  List all calendars
    list_events     List events in a calendar
    get_event       Get a single event
    create_event    Create a new event
    update_event    Update an existing event
    delete_event    Delete an event

Examples:
    service feishu calendar list_calendars
    service feishu calendar list_events calendar_id=primary
    service feishu calendar list_events calendar_id=primary start_time=2024-01-01T00:00:00+08:00
    service feishu calendar get_event calendar_id=primary event_id=xxx
    service feishu calendar create_event calendar_id=primary data='{"summary":"Meeting",...}'
    service feishu calendar update_event calendar_id=primary event_id=xxx data='{"summary":"Updated"}'
    service feishu calendar delete_event calendar_id=primary event_id=xxx
"""

import json
from typing import Any

from ..plugins import (
    calendar_list_events,
    calendar_get_event,
    calendar_create_event,
    calendar_update_event,
    calendar_delete_event,
)
from ..api import call_api


# Available actions with their descriptions
ACTIONS = {
    'list_calendars': 'List all calendars accessible by the bot',
    'list_events': 'List events in a calendar (supports time range)',
    'get_event': 'Get a single event by ID',
    'create_event': 'Create a new calendar event',
    'update_event': 'Update an existing event',
    'delete_event': 'Delete an event',
}


def get_actions() -> dict[str, str]:
    """Return available actions and their descriptions."""
    return ACTIONS


def run_action(action: str, params: dict[str, Any]) -> dict:
    """
    Execute a calendar action.

    Args:
        action: Action name (list_calendars, list_events, etc.)
        params: Parameters for the action

    Returns:
        API response as dict

    Raises:
        ValueError: If required parameters are missing
    """
    if action == 'list_calendars':
        return _list_calendars(params)
    elif action == 'list_events':
        return _list_events(params)
    elif action == 'get_event':
        return _get_event(params)
    elif action == 'create_event':
        return _create_event(params)
    elif action == 'update_event':
        return _update_event(params)
    elif action == 'delete_event':
        return _delete_event(params)
    else:
        raise ValueError(f"Unknown action: {action}")


def _require_params(params: dict, *required: str) -> None:
    """Check that required parameters are present."""
    missing = [p for p in required if p not in params]
    if missing:
        raise ValueError(f"Missing required parameters: {', '.join(missing)}")


def _list_calendars(params: dict) -> dict:
    """List all calendars."""
    return call_api(
        domain='calendar',
        method_path='calendar/v4/calendars',
        params={
            'page_size': params.get('page_size', 50),
            'page_token': params.get('page_token'),
        },
    )


def _list_events(params: dict) -> dict:
    """List events in a calendar."""
    _require_params(params, 'calendar_id')
    return calendar_list_events(
        calendar_id=params['calendar_id'],
        start_time=params.get('start_time'),
        end_time=params.get('end_time'),
        page_size=params.get('page_size', 50),
        page_token=params.get('page_token'),
    )


def _get_event(params: dict) -> dict:
    """Get a single event."""
    _require_params(params, 'calendar_id', 'event_id')
    return calendar_get_event(
        calendar_id=params['calendar_id'],
        event_id=params['event_id'],
    )


def _create_event(params: dict) -> dict:
    """Create a new event."""
    _require_params(params, 'calendar_id', 'data')

    # Parse data if it's a string
    data = params['data']
    if isinstance(data, str):
        try:
            data = json.loads(data)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in data: {e}")

    return calendar_create_event(
        calendar_id=params['calendar_id'],
        event_data=data,
    )


def _update_event(params: dict) -> dict:
    """Update an existing event."""
    _require_params(params, 'calendar_id', 'event_id', 'data')

    # Parse data if it's a string
    data = params['data']
    if isinstance(data, str):
        try:
            data = json.loads(data)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in data: {e}")

    return calendar_update_event(
        calendar_id=params['calendar_id'],
        event_id=params['event_id'],
        event_data=data,
    )


def _delete_event(params: dict) -> dict:
    """Delete an event."""
    _require_params(params, 'calendar_id', 'event_id')
    return calendar_delete_event(
        calendar_id=params['calendar_id'],
        event_id=params['event_id'],
    )
