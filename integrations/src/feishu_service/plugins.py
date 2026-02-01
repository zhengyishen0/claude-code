"""Feishu API plugins - high-level functions for common operations.

This module provides convenient wrapper functions for Feishu APIs.
Each function handles path construction and parameter formatting.

Domains covered:
- Calendar (v4): events management
- Bitable (v1): database tables and records
- VC (v1): video conference recordings
"""

from typing import Optional, Any
from .api import call_api, call_api_with_method


# =============================================================================
# Calendar API (v4) - Read + Write
# =============================================================================

def calendar_list_events(
    calendar_id: str = "primary",
    start_time: Optional[str] = None,
    end_time: Optional[str] = None,
    page_size: int = 50,
    page_token: Optional[str] = None,
) -> dict:
    """
    List calendar events within a time range.

    Args:
        calendar_id: Calendar ID, use "primary" for user's primary calendar
        start_time: Start time in RFC3339 format (e.g., "2024-01-01T00:00:00+08:00")
        end_time: End time in RFC3339 format
        page_size: Number of events per page (default 50, max 500)
        page_token: Token for pagination

    Returns:
        dict with 'items' (list of events) and 'page_token' for next page

    Example:
        >>> calendar_list_events(
        ...     start_time="2024-01-01T00:00:00+08:00",
        ...     end_time="2024-01-31T23:59:59+08:00",
        ...     page_size=20
        ... )
    """
    params = {
        "page_size": page_size,
    }
    if start_time:
        params["start_time"] = start_time
    if end_time:
        params["end_time"] = end_time
    if page_token:
        params["page_token"] = page_token

    return call_api(
        domain="calendar",
        method_path=f"calendar/v4/calendars/{calendar_id}/events",
        params=params,
    )


def calendar_get_event(calendar_id: str, event_id: str) -> dict:
    """
    Get a single calendar event by ID.

    Args:
        calendar_id: Calendar ID, use "primary" for user's primary calendar
        event_id: Event ID to retrieve

    Returns:
        dict with event details including summary, start_time, end_time, attendees

    Example:
        >>> calendar_get_event("primary", "event_xxx")
    """
    return call_api(
        domain="calendar",
        method_path=f"calendar/v4/calendars/{calendar_id}/events/{event_id}",
    )


def calendar_create_event(calendar_id: str, event_data: dict) -> dict:
    """
    Create a new calendar event.

    Note: Write operations may require approval flow in certain contexts.

    Args:
        calendar_id: Calendar ID, use "primary" for user's primary calendar
        event_data: Event data dict containing:
            - summary: Event title (required)
            - start_time: Start time with timezone (required)
            - end_time: End time with timezone (required)
            - description: Event description (optional)
            - attendees: List of attendee dicts (optional)
            - location: Event location (optional)
            - reminders: Reminder settings (optional)

    Returns:
        dict with created event details including event_id

    Example:
        >>> calendar_create_event("primary", {
        ...     "summary": "Team Meeting",
        ...     "start_time": {
        ...         "timestamp": "1704067200",
        ...         "timezone": "Asia/Shanghai"
        ...     },
        ...     "end_time": {
        ...         "timestamp": "1704070800",
        ...         "timezone": "Asia/Shanghai"
        ...     },
        ...     "description": "Weekly sync",
        ...     "attendees": [{"user_id": "ou_xxx", "type": "user"}]
        ... })
    """
    return call_api(
        domain="calendar",
        method_path=f"calendar/v4/calendars/{calendar_id}/events",
        body=event_data,
    )


def calendar_update_event(
    calendar_id: str,
    event_id: str,
    event_data: dict,
) -> dict:
    """
    Update an existing calendar event.

    Args:
        calendar_id: Calendar ID, use "primary" for user's primary calendar
        event_id: Event ID to update
        event_data: Updated event data (partial update supported)

    Returns:
        dict with updated event details

    Example:
        >>> calendar_update_event("primary", "event_xxx", {
        ...     "summary": "Updated Meeting Title",
        ...     "description": "New description"
        ... })
    """
    return call_api_with_method(
        http_method="PATCH",
        method_path=f"calendar/v4/calendars/{calendar_id}/events/{event_id}",
        body=event_data,
    )


def calendar_delete_event(calendar_id: str, event_id: str) -> dict:
    """
    Delete a calendar event.

    Args:
        calendar_id: Calendar ID, use "primary" for user's primary calendar
        event_id: Event ID to delete

    Returns:
        dict with success status

    Example:
        >>> calendar_delete_event("primary", "event_xxx")
    """
    return call_api_with_method(
        http_method="DELETE",
        method_path=f"calendar/v4/calendars/{calendar_id}/events/{event_id}",
    )


# =============================================================================
# Bitable API (v1) - Read Only
# =============================================================================

def bitable_list_tables(
    app_token: str,
    page_size: int = 20,
    page_token: Optional[str] = None,
) -> dict:
    """
    List all tables in a Bitable base.

    Args:
        app_token: Bitable app token (from the base URL)
        page_size: Number of tables per page (default 20)
        page_token: Token for pagination

    Returns:
        dict with 'items' (list of tables) including table_id and name

    Example:
        >>> bitable_list_tables("bascnxxx")
    """
    params = {
        "page_size": page_size,
    }
    if page_token:
        params["page_token"] = page_token

    return call_api(
        domain="bitable",
        method_path=f"bitable/v1/apps/{app_token}/tables",
        params=params,
    )


def bitable_list_records(
    app_token: str,
    table_id: str,
    page_size: int = 20,
    page_token: Optional[str] = None,
    view_id: Optional[str] = None,
    filter_expr: Optional[str] = None,
    sort: Optional[list] = None,
) -> dict:
    """
    List records in a Bitable table.

    Args:
        app_token: Bitable app token
        table_id: Table ID within the base
        page_size: Number of records per page (default 20, max 500)
        page_token: Token for pagination
        view_id: Optional view ID to filter by
        filter_expr: Optional filter expression
        sort: Optional sort configuration

    Returns:
        dict with 'items' (list of records) and pagination info

    Example:
        >>> bitable_list_records("bascnxxx", "tblxxx", page_size=50)
    """
    params = {
        "page_size": page_size,
    }
    if page_token:
        params["page_token"] = page_token
    if view_id:
        params["view_id"] = view_id
    if filter_expr:
        params["filter"] = filter_expr
    if sort:
        params["sort"] = sort

    return call_api(
        domain="bitable",
        method_path=f"bitable/v1/apps/{app_token}/tables/{table_id}/records",
        params=params,
    )


def bitable_get_record(
    app_token: str,
    table_id: str,
    record_id: str,
) -> dict:
    """
    Get a single record from a Bitable table.

    Args:
        app_token: Bitable app token
        table_id: Table ID
        record_id: Record ID to retrieve

    Returns:
        dict with record data including fields

    Example:
        >>> bitable_get_record("bascnxxx", "tblxxx", "recxxx")
    """
    return call_api(
        domain="bitable",
        method_path=f"bitable/v1/apps/{app_token}/tables/{table_id}/records/{record_id}",
    )


def bitable_list_fields(
    app_token: str,
    table_id: str,
    page_size: int = 100,
    page_token: Optional[str] = None,
) -> dict:
    """
    List all fields (columns) in a Bitable table.

    Args:
        app_token: Bitable app token
        table_id: Table ID
        page_size: Number of fields per page (default 100)
        page_token: Token for pagination

    Returns:
        dict with 'items' (list of fields) including field_id, name, type

    Example:
        >>> bitable_list_fields("bascnxxx", "tblxxx")
    """
    params = {
        "page_size": page_size,
    }
    if page_token:
        params["page_token"] = page_token

    return call_api(
        domain="bitable",
        method_path=f"bitable/v1/apps/{app_token}/tables/{table_id}/fields",
        params=params,
    )


# =============================================================================
# VC API (v1) - Read + Write
# =============================================================================

def vc_get_recording(meeting_id: str) -> dict:
    """
    Get recording info and URL for a meeting.

    Args:
        meeting_id: Meeting ID to get recording for

    Returns:
        dict with recording info including URL, duration, status

    Example:
        >>> vc_get_recording("7xxx")
    """
    return call_api(
        domain="vc",
        method_path=f"vc/v1/meetings/{meeting_id}/recording",
    )


def vc_list_recordings(
    start_time: str,
    end_time: str,
    page_size: int = 20,
    page_token: Optional[str] = None,
) -> dict:
    """
    List recordings within a time range.

    Args:
        start_time: Start time in Unix timestamp (seconds)
        end_time: End time in Unix timestamp (seconds)
        page_size: Number of recordings per page (default 20)
        page_token: Token for pagination

    Returns:
        dict with 'recording_list' and pagination info

    Example:
        >>> vc_list_recordings(
        ...     start_time="1704067200",
        ...     end_time="1704153600",
        ...     page_size=10
        ... )
    """
    params = {
        "start_time": start_time,
        "end_time": end_time,
        "page_size": page_size,
    }
    if page_token:
        params["page_token"] = page_token

    return call_api(
        domain="vc",
        method_path="vc/v1/meetings/list_by_no",
        params=params,
    )


def vc_set_recording_permission(
    meeting_id: str,
    permission_data: dict,
) -> dict:
    """
    Set sharing permission for a meeting recording.

    Note: This operation may require user token for certain permissions.

    Args:
        meeting_id: Meeting ID
        permission_data: Permission settings dict containing:
            - permission_type: Permission level (e.g., "same_tenant", "anyone_with_link")
            - viewer_list: List of viewer IDs (optional)

    Returns:
        dict with operation result

    Example:
        >>> vc_set_recording_permission("7xxx", {
        ...     "permission_type": "same_tenant"
        ... })
    """
    return call_api_with_method(
        http_method="PATCH",
        method_path=f"vc/v1/meetings/{meeting_id}/recording/set_permission",
        body=permission_data,
    )


# =============================================================================
# Convenience Exports
# =============================================================================

__all__ = [
    # Calendar
    "calendar_list_events",
    "calendar_get_event",
    "calendar_create_event",
    "calendar_update_event",
    "calendar_delete_event",
    # Bitable
    "bitable_list_tables",
    "bitable_list_records",
    "bitable_get_record",
    "bitable_list_fields",
    # VC
    "vc_get_recording",
    "vc_list_recordings",
    "vc_set_recording_permission",
]
