"""
Feishu Bot Handler - Message processing with Claude Code integration

Handles:
- DM: Always respond
- Group: Only respond when @mentioned, but include full history
- Persistence: cc --resume with deterministic UUID per chat
"""

import json
import subprocess
import uuid
from pathlib import Path
from datetime import datetime
from typing import Optional

# Storage directory
CHATS_DIR = Path.home() / '.config' / 'api' / 'feishu' / 'chats'

# Namespace for deterministic UUID generation
NAMESPACE = uuid.UUID('f1e2d3c4-b5a6-4789-8901-234567890abc')


def get_session_uuid(chat_id: str) -> str:
    """Generate deterministic UUID from Feishu chat_id"""
    return str(uuid.uuid5(NAMESPACE, chat_id))


def get_chat_file(chat_id: str) -> Path:
    """Get path to chat history file"""
    CHATS_DIR.mkdir(parents=True, exist_ok=True)
    return CHATS_DIR / f"{chat_id}.json"


def load_chat(chat_id: str) -> dict:
    """Load chat history from file"""
    chat_file = get_chat_file(chat_id)
    if chat_file.exists():
        return json.loads(chat_file.read_text())
    return {
        "chat_id": chat_id,
        "cc_session": get_session_uuid(chat_id),
        "messages": []
    }


def save_chat(chat_id: str, chat_data: dict):
    """Save chat history to file"""
    chat_file = get_chat_file(chat_id)
    chat_file.write_text(json.dumps(chat_data, indent=2, ensure_ascii=False))


def store_message(chat_id: str, user: str, content: str, is_bot: bool = False):
    """Store a message in chat history"""
    chat = load_chat(chat_id)
    chat["messages"].append({
        "user": user,
        "content": content,
        "timestamp": datetime.now().isoformat(),
        "is_bot": is_bot
    })
    save_chat(chat_id, chat)


def format_history_for_cc(chat_data: dict) -> str:
    """Format chat history as text for CC"""
    lines = []
    for msg in chat_data["messages"]:
        prefix = "[Bot]" if msg.get("is_bot") else msg["user"]
        lines.append(f"{prefix}: {msg['content']}")
    return "\n".join(lines)


def parse_message_content(content_json: str) -> str:
    """Parse Feishu message content JSON to plain text"""
    try:
        content = json.loads(content_json)
        # Text message
        if "text" in content:
            return content["text"]
        # Other types - return as-is or extract
        return str(content)
    except Exception:
        return content_json


def is_bot_mentioned(event) -> bool:
    """Check if bot is @mentioned in the message"""
    mentions = getattr(event.message, 'mentions', None)
    if mentions:
        for mention in mentions:
            # Check if it's the bot being mentioned
            if getattr(mention, 'id', {}).get('open_id') == 'bot' or \
               getattr(mention, 'key', '') == '@_all' or \
               getattr(mention, 'name', '').lower() in ['cc', 'bot']:
                return True
    # Also check content for @_ pattern (bot mention marker)
    content = parse_message_content(event.message.content)
    return '@_user_' in content or '@CC' in content or '@cc' in content


def call_cc(session_uuid: str, prompt: str) -> str:
    """Call cc --resume with the given prompt"""
    try:
        result = subprocess.run(
            ['claude', '--dangerously-skip-permissions', '--resume', session_uuid, '--print', '-p', prompt],
            capture_output=True,
            text=True,
            timeout=120  # 2 minute timeout
        )
        if result.returncode == 0:
            return result.stdout.strip()
        else:
            return f"Error: {result.stderr.strip()}"
    except subprocess.TimeoutExpired:
        return "Response timed out"
    except FileNotFoundError:
        return "cc command not found"
    except Exception as e:
        return f"Error: {str(e)}"


# User nickname cache
_nickname_cache = {}


def get_nickname(open_id: str, default: str = "User") -> str:
    """Get user nickname from cache or return default"""
    # TODO: Implement Feishu API call to resolve nickname
    # For now, use cache or default
    return _nickname_cache.get(open_id, default)


def set_nickname(open_id: str, nickname: str):
    """Cache a user's nickname"""
    _nickname_cache[open_id] = nickname


def handle_message(event) -> Optional[str]:
    """
    Main message handler.

    Returns response text to send, or None if no response needed.
    """
    message = event.message
    chat_id = message.chat_id
    chat_type = message.chat_type  # "p2p" for DM, "group" for group
    content = parse_message_content(message.content)

    # Get sender info
    sender_id = event.sender.sender_id.open_id
    # Try to get nickname from mentions or use cached
    sender_name = get_nickname(sender_id, f"User_{sender_id[-4:]}")

    # Try to extract nickname from event if available
    if hasattr(event.sender, 'sender_id'):
        # Cache any nickname we can find
        pass  # TODO: extract from event

    # Store the message
    store_message(chat_id, sender_name, content)

    # Group chat: only respond if @mentioned
    if chat_type == "group" and not is_bot_mentioned(event):
        return None  # Silent storage

    # Load full history and call CC
    chat = load_chat(chat_id)
    history = format_history_for_cc(chat)
    session_uuid = chat["cc_session"]

    # Call cc with history as context
    prompt = f"Chat history:\n{history}\n\nRespond to the latest message."
    response = call_cc(session_uuid, prompt)

    # Store bot response
    store_message(chat_id, "Bot", response, is_bot=True)

    return response
