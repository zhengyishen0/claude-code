"""IM (Instant Messaging) CLI commands.

Send messages, manage chats, and reply in threads.

Actions:
    send              Send a text message
    send_card         Send an interactive card message
    reply             Reply to a message
    reply_in_thread   Reply in a thread/topic (creates or continues a thread)
    list_chats        List chats the bot is in

Examples:
    service feishu im send chat_id=oc_XXX text="Hello world"
    service feishu im send_card chat_id=oc_XXX card='{"config":{},"elements":[...]}'
    service feishu im reply message_id=om_XXX text="Thanks!"
    service feishu im reply_in_thread message_id=om_XXX text="Thread reply"
    service feishu im list_chats
"""

import json
from typing import Any

from ..api import call_api


# Available actions with their descriptions
ACTIONS = {
    'send': 'Send a text message to a chat',
    'send_card': 'Send an interactive card message',
    'reply': 'Reply to a specific message',
    'reply_in_thread': 'Reply in a thread/topic (creates or continues a thread)',
    'list_chats': 'List chats the bot is a member of',
}


def get_actions() -> dict[str, str]:
    """Return available actions and their descriptions."""
    return ACTIONS


def run_action(action: str, params: dict[str, Any]) -> dict:
    """
    Execute an IM action.

    Args:
        action: Action name (send, reply, etc.)
        params: Parameters for the action

    Returns:
        API response as dict

    Raises:
        ValueError: If required parameters are missing
    """
    if action == 'send':
        return _send_message(params)
    elif action == 'send_card':
        return _send_card(params)
    elif action == 'reply':
        return _reply_message(params)
    elif action == 'reply_in_thread':
        return _reply_in_thread(params)
    elif action == 'list_chats':
        return _list_chats(params)
    else:
        raise ValueError(f"Unknown action: {action}")


def _require_params(params: dict, *required: str) -> None:
    """Check that required parameters are present."""
    missing = [p for p in required if p not in params]
    if missing:
        raise ValueError(f"Missing required parameters: {', '.join(missing)}")


def _send_message(params: dict) -> dict:
    """Send a text message to a chat."""
    _require_params(params, 'chat_id', 'text')

    content = json.dumps({'text': params['text']})

    return call_api(
        domain='im',
        method_path='im/v1/messages',
        params={'receive_id_type': 'chat_id'},
        body={
            'receive_id': params['chat_id'],
            'msg_type': 'text',
            'content': content,
        },
    )


def _send_card(params: dict) -> dict:
    """Send an interactive card message."""
    _require_params(params, 'chat_id', 'card')

    # Parse card if it's a string
    card = params['card']
    if isinstance(card, str):
        try:
            card = json.loads(card)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in card: {e}")

    content = json.dumps(card)

    return call_api(
        domain='im',
        method_path='im/v1/messages',
        params={'receive_id_type': 'chat_id'},
        body={
            'receive_id': params['chat_id'],
            'msg_type': 'interactive',
            'content': content,
        },
    )


def _reply_message(params: dict) -> dict:
    """Reply to a specific message."""
    _require_params(params, 'message_id', 'text')

    content = json.dumps({'text': params['text']})

    return call_api(
        domain='im',
        method_path=f"im/v1/messages/{params['message_id']}/reply",
        body={
            'msg_type': 'text',
            'content': content,
        },
    )


def _reply_in_thread(params: dict) -> dict:
    """Reply in a thread/topic (creates or continues a thread)."""
    _require_params(params, 'message_id', 'text')

    content = json.dumps({'text': params['text']})

    return call_api(
        domain='im',
        method_path=f"im/v1/messages/{params['message_id']}/reply",
        body={
            'msg_type': 'text',
            'content': content,
            'reply_in_thread': True,
        },
    )


def _list_chats(params: dict) -> dict:
    """List chats the bot is a member of."""
    return call_api(
        domain='im',
        method_path='im/v1/chats',
        params={
            'page_size': params.get('page_size', 20),
            'page_token': params.get('page_token'),
        },
    )


