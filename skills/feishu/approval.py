"""Calendar approval flow using Feishu interactive message cards.

This module implements an approval workflow for calendar operations:
1. When a calendar action is requested, it's stored as pending
2. An interactive card is sent to the user for approval
3. User clicks Approve/Reject button
4. Callback handler executes or cancels the action

Usage:
    from feishu.approval import (
        request_calendar_create,
        request_calendar_update,
        request_calendar_delete,
        handle_card_callback,
    )

    # Request approval for creating an event
    action_id = request_calendar_create(chat_id, "primary", {
        "summary": "Team Meeting",
        "start_time": {"timestamp": "1704067200"},
        "end_time": {"timestamp": "1704070800"},
    })

    # Later, when button is clicked:
    result = handle_card_callback(callback_data)
"""

import json
import time
import uuid
from datetime import datetime
from typing import Optional, Any

from .api import call_api
from .plugins import (
    calendar_create_event,
    calendar_update_event,
    calendar_delete_event,
    calendar_get_event,
)


# =============================================================================
# Pending Actions Store
# =============================================================================

# In-memory store for pending calendar actions
# action_id -> {type, data, chat_id, user_id, expires, calendar_id, event_id, event_info}
_pending_actions: dict[str, dict] = {}

# Expiration time in seconds (1 hour)
_EXPIRATION_SECONDS = 3600


def _generate_action_id() -> str:
    """Generate a unique action ID."""
    return f"cal_{uuid.uuid4().hex[:12]}"


def _store_pending_action(
    action_type: str,
    chat_id: str,
    calendar_id: str,
    data: dict,
    event_id: Optional[str] = None,
    event_info: Optional[dict] = None,
) -> str:
    """
    Store a pending calendar action.

    Args:
        action_type: Type of action ('create', 'update', 'delete')
        chat_id: Chat ID where the approval card will be sent
        calendar_id: Calendar ID for the operation
        data: Event data for create/update operations
        event_id: Event ID for update/delete operations
        event_info: Existing event info for display purposes

    Returns:
        action_id: Unique identifier for this pending action
    """
    action_id = _generate_action_id()
    expires = time.time() + _EXPIRATION_SECONDS

    _pending_actions[action_id] = {
        "type": action_type,
        "chat_id": chat_id,
        "calendar_id": calendar_id,
        "data": data,
        "event_id": event_id,
        "event_info": event_info,
        "expires": expires,
        "created_at": time.time(),
    }

    return action_id


def _get_pending_action(action_id: str) -> Optional[dict]:
    """
    Retrieve a pending action by ID.

    Returns None if action doesn't exist or has expired.
    """
    action = _pending_actions.get(action_id)
    if not action:
        return None

    # Check expiration
    if time.time() > action["expires"]:
        del _pending_actions[action_id]
        return None

    return action


def _remove_pending_action(action_id: str) -> Optional[dict]:
    """Remove and return a pending action."""
    return _pending_actions.pop(action_id, None)


def cleanup_expired_actions() -> int:
    """
    Clean up expired pending actions.

    Returns:
        Number of actions cleaned up
    """
    now = time.time()
    expired = [
        action_id
        for action_id, action in _pending_actions.items()
        if now > action["expires"]
    ]

    for action_id in expired:
        del _pending_actions[action_id]

    return len(expired)


# =============================================================================
# Card Builder Functions
# =============================================================================

def _format_timestamp(timestamp: str) -> str:
    """Convert Unix timestamp to human-readable format."""
    try:
        ts = int(timestamp)
        dt = datetime.fromtimestamp(ts)
        return dt.strftime("%Y-%m-%d %H:%M")
    except (ValueError, TypeError):
        return timestamp


def _format_event_time(event_data: dict) -> str:
    """Format event time from event data."""
    start_time = event_data.get("start_time", {})
    end_time = event_data.get("end_time", {})

    # Handle different time formats
    if isinstance(start_time, dict):
        start_ts = start_time.get("timestamp", "")
        start_str = _format_timestamp(start_ts) if start_ts else "N/A"
    else:
        start_str = str(start_time)

    if isinstance(end_time, dict):
        end_ts = end_time.get("timestamp", "")
        end_str = _format_timestamp(end_ts) if end_ts else "N/A"
    else:
        end_str = str(end_time)

    return f"{start_str} - {end_str}"


def build_calendar_create_card(action_id: str, event_data: dict) -> dict:
    """
    Build interactive card JSON for "Create Event" approval.

    Args:
        action_id: Unique action identifier
        event_data: Event data dict with summary, start_time, end_time, etc.

    Returns:
        Interactive card JSON structure
    """
    summary = event_data.get("summary", "Untitled Event")
    time_str = _format_event_time(event_data)
    description = event_data.get("description", "")
    location = event_data.get("location", {})
    location_str = location.get("name", "") if isinstance(location, dict) else str(location) if location else ""

    # Build content lines
    content_lines = [
        f"**Action**: Create Event",
        f"**Title**: {summary}",
        f"**Time**: {time_str}",
    ]
    if description:
        content_lines.append(f"**Description**: {description[:100]}{'...' if len(description) > 100 else ''}")
    if location_str:
        content_lines.append(f"**Location**: {location_str}")

    return {
        "config": {"wide_screen_mode": True},
        "header": {
            "title": {"tag": "plain_text", "content": "Calendar Action Request"},
            "template": "blue"
        },
        "elements": [
            {
                "tag": "div",
                "text": {
                    "tag": "lark_md",
                    "content": "\n".join(content_lines)
                }
            },
            {
                "tag": "action",
                "actions": [
                    {
                        "tag": "button",
                        "text": {"tag": "plain_text", "content": "Approve"},
                        "type": "primary",
                        "value": {"action": "approve", "action_id": action_id}
                    },
                    {
                        "tag": "button",
                        "text": {"tag": "plain_text", "content": "Reject"},
                        "type": "danger",
                        "value": {"action": "reject", "action_id": action_id}
                    }
                ]
            }
        ]
    }


def build_calendar_update_card(
    action_id: str,
    calendar_id: str,
    event_id: str,
    event_data: dict,
    existing_info: Optional[dict] = None,
) -> dict:
    """
    Build interactive card JSON for "Update Event" approval.

    Args:
        action_id: Unique action identifier
        calendar_id: Calendar ID
        event_id: Event ID being updated
        event_data: New event data for the update
        existing_info: Optional existing event info for comparison

    Returns:
        Interactive card JSON structure
    """
    # Show what's being changed
    changes = []

    if "summary" in event_data:
        old_title = existing_info.get("summary", "N/A") if existing_info else "N/A"
        changes.append(f"**Title**: {old_title} -> {event_data['summary']}")

    if "start_time" in event_data or "end_time" in event_data:
        new_time = _format_event_time(event_data)
        if existing_info:
            old_time = _format_event_time(existing_info)
            changes.append(f"**Time**: {old_time} -> {new_time}")
        else:
            changes.append(f"**New Time**: {new_time}")

    if "description" in event_data:
        desc = event_data["description"]
        changes.append(f"**Description**: {desc[:100]}{'...' if len(desc) > 100 else ''}")

    if "location" in event_data:
        location = event_data["location"]
        loc_str = location.get("name", "") if isinstance(location, dict) else str(location)
        changes.append(f"**Location**: {loc_str}")

    if not changes:
        changes.append("*(No specific changes shown)*")

    content_lines = [
        f"**Action**: Update Event",
        f"**Event ID**: {event_id[:20]}..." if len(event_id) > 20 else f"**Event ID**: {event_id}",
        "",
        "**Changes**:",
    ] + changes

    return {
        "config": {"wide_screen_mode": True},
        "header": {
            "title": {"tag": "plain_text", "content": "Calendar Action Request"},
            "template": "orange"
        },
        "elements": [
            {
                "tag": "div",
                "text": {
                    "tag": "lark_md",
                    "content": "\n".join(content_lines)
                }
            },
            {
                "tag": "action",
                "actions": [
                    {
                        "tag": "button",
                        "text": {"tag": "plain_text", "content": "Approve"},
                        "type": "primary",
                        "value": {"action": "approve", "action_id": action_id}
                    },
                    {
                        "tag": "button",
                        "text": {"tag": "plain_text", "content": "Reject"},
                        "type": "danger",
                        "value": {"action": "reject", "action_id": action_id}
                    }
                ]
            }
        ]
    }


def build_calendar_delete_card(
    action_id: str,
    calendar_id: str,
    event_id: str,
    event_info: Optional[dict] = None,
) -> dict:
    """
    Build interactive card JSON for "Delete Event" approval.

    Args:
        action_id: Unique action identifier
        calendar_id: Calendar ID
        event_id: Event ID being deleted
        event_info: Event info for display (fetched before creating card)

    Returns:
        Interactive card JSON structure
    """
    if event_info:
        summary = event_info.get("summary", "Untitled Event")
        time_str = _format_event_time(event_info)
        description = event_info.get("description", "")
    else:
        summary = "Unknown Event"
        time_str = "N/A"
        description = ""

    content_lines = [
        f"**Action**: Delete Event",
        f"**Title**: {summary}",
        f"**Time**: {time_str}",
    ]
    if description:
        content_lines.append(f"**Description**: {description[:100]}{'...' if len(description) > 100 else ''}")

    content_lines.append("")
    content_lines.append("*This action cannot be undone.*")

    return {
        "config": {"wide_screen_mode": True},
        "header": {
            "title": {"tag": "plain_text", "content": "Calendar Action Request"},
            "template": "red"
        },
        "elements": [
            {
                "tag": "div",
                "text": {
                    "tag": "lark_md",
                    "content": "\n".join(content_lines)
                }
            },
            {
                "tag": "action",
                "actions": [
                    {
                        "tag": "button",
                        "text": {"tag": "plain_text", "content": "Approve"},
                        "type": "primary",
                        "value": {"action": "approve", "action_id": action_id}
                    },
                    {
                        "tag": "button",
                        "text": {"tag": "plain_text", "content": "Reject"},
                        "type": "danger",
                        "value": {"action": "reject", "action_id": action_id}
                    }
                ]
            }
        ]
    }


def _build_result_card(
    action_type: str,
    approved: bool,
    user_name: str,
    details: str = "",
    error: Optional[str] = None,
) -> dict:
    """
    Build result card to replace the approval card after action is taken.

    Args:
        action_type: Type of action ('create', 'update', 'delete')
        approved: Whether the action was approved
        user_name: Name of the user who took the action
        details: Additional details about the result
        error: Error message if action failed

    Returns:
        Updated card JSON structure
    """
    action_display = action_type.capitalize()
    status = "Approved" if approved else "Rejected"
    template = "green" if approved and not error else "red" if error or not approved else "grey"

    content_lines = [
        f"**Action**: {action_display} Event",
        f"**Status**: {status} by {user_name}",
    ]

    if details:
        content_lines.append(f"**Result**: {details}")

    if error:
        content_lines.append(f"**Error**: {error}")

    return {
        "config": {"wide_screen_mode": True},
        "header": {
            "title": {"tag": "plain_text", "content": f"Calendar Action - {status}"},
            "template": template
        },
        "elements": [
            {
                "tag": "div",
                "text": {
                    "tag": "lark_md",
                    "content": "\n".join(content_lines)
                }
            }
        ]
    }


# =============================================================================
# Request Functions
# =============================================================================

def _send_interactive_card(chat_id: str, card: dict) -> dict:
    """Send an interactive message card to a chat."""
    return call_api(
        domain="im",
        method_path="im/v1/messages",
        params={"receive_id_type": "chat_id"},
        body={
            "receive_id": chat_id,
            "msg_type": "interactive",
            "content": json.dumps(card)
        }
    )


def request_calendar_create(
    chat_id: str,
    calendar_id: str,
    event_data: dict,
) -> str:
    """
    Request approval for creating a calendar event.

    Stores the pending action and sends an approval card to the chat.

    Args:
        chat_id: Chat ID to send the approval card
        calendar_id: Calendar ID (e.g., "primary")
        event_data: Event data dict with summary, start_time, end_time, etc.

    Returns:
        action_id: Unique identifier for tracking this request
    """
    # Store pending action
    action_id = _store_pending_action(
        action_type="create",
        chat_id=chat_id,
        calendar_id=calendar_id,
        data=event_data,
    )

    # Build and send approval card
    card = build_calendar_create_card(action_id, event_data)
    result = _send_interactive_card(chat_id, card)

    if result.get("error"):
        # Clean up pending action if card failed to send
        _remove_pending_action(action_id)
        raise RuntimeError(f"Failed to send approval card: {result.get('msg')}")

    return action_id


def request_calendar_update(
    chat_id: str,
    calendar_id: str,
    event_id: str,
    event_data: dict,
) -> str:
    """
    Request approval for updating a calendar event.

    Stores the pending action and sends an approval card to the chat.

    Args:
        chat_id: Chat ID to send the approval card
        calendar_id: Calendar ID (e.g., "primary")
        event_id: Event ID to update
        event_data: Updated event data

    Returns:
        action_id: Unique identifier for tracking this request
    """
    # Fetch existing event info for comparison
    existing_info = None
    try:
        result = calendar_get_event(calendar_id, event_id)
        if not result.get("error"):
            existing_info = result.get("event", result)
    except Exception:
        pass  # Continue without existing info

    # Store pending action
    action_id = _store_pending_action(
        action_type="update",
        chat_id=chat_id,
        calendar_id=calendar_id,
        data=event_data,
        event_id=event_id,
        event_info=existing_info,
    )

    # Build and send approval card
    card = build_calendar_update_card(action_id, calendar_id, event_id, event_data, existing_info)
    result = _send_interactive_card(chat_id, card)

    if result.get("error"):
        _remove_pending_action(action_id)
        raise RuntimeError(f"Failed to send approval card: {result.get('msg')}")

    return action_id


def request_calendar_delete(
    chat_id: str,
    calendar_id: str,
    event_id: str,
) -> str:
    """
    Request approval for deleting a calendar event.

    Fetches event info first for display, then stores the pending action
    and sends an approval card to the chat.

    Args:
        chat_id: Chat ID to send the approval card
        calendar_id: Calendar ID (e.g., "primary")
        event_id: Event ID to delete

    Returns:
        action_id: Unique identifier for tracking this request
    """
    # Fetch event info for display
    event_info = None
    try:
        result = calendar_get_event(calendar_id, event_id)
        if not result.get("error"):
            event_info = result.get("event", result)
    except Exception:
        pass  # Continue without event info

    # Store pending action
    action_id = _store_pending_action(
        action_type="delete",
        chat_id=chat_id,
        calendar_id=calendar_id,
        data={},
        event_id=event_id,
        event_info=event_info,
    )

    # Build and send approval card
    card = build_calendar_delete_card(action_id, calendar_id, event_id, event_info)
    result = _send_interactive_card(chat_id, card)

    if result.get("error"):
        _remove_pending_action(action_id)
        raise RuntimeError(f"Failed to send approval card: {result.get('msg')}")

    return action_id


# =============================================================================
# Callback Handler
# =============================================================================

def handle_card_callback(callback_data: dict) -> dict:
    """
    Handle the button click callback from an approval card.

    Args:
        callback_data: Callback data from Feishu, containing:
            - action: The button value dict with 'action' and 'action_id'
            - operator: User info who clicked the button

    Returns:
        Updated card JSON to replace the original card
    """
    # Extract action info from callback
    action_value = callback_data.get("action", {}).get("value", {})
    if isinstance(action_value, str):
        try:
            action_value = json.loads(action_value)
        except json.JSONDecodeError:
            action_value = {}

    action = action_value.get("action")  # 'approve' or 'reject'
    action_id = action_value.get("action_id")

    # Get operator info
    operator = callback_data.get("operator", {})
    user_name = operator.get("user_name", "Unknown User")
    user_id = operator.get("user_id", operator.get("open_id", ""))

    if not action or not action_id:
        return _build_result_card(
            action_type="unknown",
            approved=False,
            user_name=user_name,
            error="Invalid callback data"
        )

    # Get pending action
    pending = _remove_pending_action(action_id)
    if not pending:
        return _build_result_card(
            action_type="unknown",
            approved=False,
            user_name=user_name,
            error="Action not found or expired"
        )

    action_type = pending["type"]
    calendar_id = pending["calendar_id"]

    # Handle rejection
    if action == "reject":
        return _build_result_card(
            action_type=action_type,
            approved=False,
            user_name=user_name,
            details="Action was cancelled"
        )

    # Handle approval - execute the calendar action
    if action == "approve":
        try:
            if action_type == "create":
                result = calendar_create_event(calendar_id, pending["data"])
                if result.get("error"):
                    return _build_result_card(
                        action_type=action_type,
                        approved=True,
                        user_name=user_name,
                        error=result.get("msg", "Failed to create event")
                    )
                event_id = result.get("event", {}).get("event_id", "created")
                return _build_result_card(
                    action_type=action_type,
                    approved=True,
                    user_name=user_name,
                    details=f"Event created: {event_id}"
                )

            elif action_type == "update":
                event_id = pending["event_id"]
                result = calendar_update_event(calendar_id, event_id, pending["data"])
                if result.get("error"):
                    return _build_result_card(
                        action_type=action_type,
                        approved=True,
                        user_name=user_name,
                        error=result.get("msg", "Failed to update event")
                    )
                return _build_result_card(
                    action_type=action_type,
                    approved=True,
                    user_name=user_name,
                    details="Event updated successfully"
                )

            elif action_type == "delete":
                event_id = pending["event_id"]
                result = calendar_delete_event(calendar_id, event_id)
                if result.get("error"):
                    return _build_result_card(
                        action_type=action_type,
                        approved=True,
                        user_name=user_name,
                        error=result.get("msg", "Failed to delete event")
                    )
                return _build_result_card(
                    action_type=action_type,
                    approved=True,
                    user_name=user_name,
                    details="Event deleted successfully"
                )

            else:
                return _build_result_card(
                    action_type=action_type,
                    approved=True,
                    user_name=user_name,
                    error=f"Unknown action type: {action_type}"
                )

        except Exception as e:
            return _build_result_card(
                action_type=action_type,
                approved=True,
                user_name=user_name,
                error=str(e)
            )

    # Unknown action
    return _build_result_card(
        action_type=action_type,
        approved=False,
        user_name=user_name,
        error=f"Unknown action: {action}"
    )


# =============================================================================
# Utility Functions
# =============================================================================

def get_pending_action_count() -> int:
    """Get the number of pending actions."""
    return len(_pending_actions)


def get_pending_action_info(action_id: str) -> Optional[dict]:
    """
    Get info about a pending action (without removing it).

    Returns summary info suitable for display, not the full action data.
    """
    action = _get_pending_action(action_id)
    if not action:
        return None

    return {
        "action_id": action_id,
        "type": action["type"],
        "calendar_id": action["calendar_id"],
        "event_id": action.get("event_id"),
        "created_at": action["created_at"],
        "expires": action["expires"],
        "expires_in": int(action["expires"] - time.time()),
    }


# =============================================================================
# Exports
# =============================================================================

__all__ = [
    # Card builders
    "build_calendar_create_card",
    "build_calendar_update_card",
    "build_calendar_delete_card",
    # Request functions
    "request_calendar_create",
    "request_calendar_update",
    "request_calendar_delete",
    # Callback handler
    "handle_card_callback",
    # Utility functions
    "cleanup_expired_actions",
    "get_pending_action_count",
    "get_pending_action_info",
]
