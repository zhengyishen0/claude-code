"""IM (Instant Messaging) CLI commands.

Send messages, manage chats, and get bot information.

Actions:
    send        Send a text message
    send_card   Send an interactive card message
    reply       Reply to a message
    list_chats  List chats the bot is in
    bot_info    Get bot information

Examples:
    service feishu im send chat_id=oc_XXX text="Hello world"
    service feishu im send_card chat_id=oc_XXX card='{"config":{},"elements":[...]}'
    service feishu im reply message_id=om_XXX text="Thanks!"
    service feishu im list_chats
    service feishu im bot_info
"""

import json
from typing import Any

from ..api import call_api


# Available actions with their descriptions
ACTIONS = {
    'send': 'Send a text message to a chat',
    'send_card': 'Send an interactive card message',
    'reply': 'Reply to a specific message',
    'list_chats': 'List chats the bot is a member of',
    'bot_info': 'Get information about the bot',
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
    elif action == 'list_chats':
        return _list_chats(params)
    elif action == 'bot_info':
        return _bot_info(params)
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


def _bot_info(params: dict) -> dict:
    """Get information about the bot."""
    return call_api(
        domain='im',
        method_path='im/v1/bots/me',
    )
