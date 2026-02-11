"""
Feishu Bot Handler - Message processing with Claude Code integration

Handles:
- Each topic/thread has its own fresh Claude session
- DM: Each user message creates a new topic with fresh context
- Group: Each thread has its own session
- Session ID based on topic root message ID (not chat_id)
- Concurrent message processing via ThreadPoolExecutor
"""

import json
import subprocess
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Optional

# Thread pool for concurrent Claude calls
# This allows multiple messages to be processed simultaneously
# without blocking the WebSocket event loop
_executor = ThreadPoolExecutor(max_workers=10)


def get_executor() -> ThreadPoolExecutor:
    """Get the shared thread pool executor."""
    return _executor

# System prompt file path
SYSTEM_PROMPT_FILE = Path(__file__).parent / 'system_prompt.md'

# Namespace for deterministic UUID generation
NAMESPACE = uuid.UUID('f1e2d3c4-b5a6-4789-8901-234567890abc')


def load_system_prompt() -> str:
    """Load system prompt from file"""
    if SYSTEM_PROMPT_FILE.exists():
        return SYSTEM_PROMPT_FILE.read_text()
    return ""


def get_topic_session_uuid(topic_root_id: str) -> str:
    """Generate deterministic UUID from topic root message ID.

    Each topic (thread) gets its own fresh Claude session.
    """
    return str(uuid.uuid5(NAMESPACE, topic_root_id))


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
            # Get mention name (bot's display name)
            mention_name = getattr(mention, 'name', '').lower()
            mention_key = getattr(mention, 'key', '')

            # Check if it's the bot being mentioned
            if mention_name in ['cc', 'bot', '有谱', 'yep']:
                return True
            if mention_key == '@_all':
                return True
            # Check if mention key starts with @_user_ (bot mention marker)
            if mention_key.startswith('@_user_'):
                return True

    # Also check content for direct @mentions
    content = parse_message_content(event.message.content)
    return '@CC' in content or '@cc' in content or '@有谱' in content


def call_cc(session_uuid: str, prompt: str, is_new_topic: bool = True) -> str:
    """Call claude with the given prompt.

    Args:
        session_uuid: The session UUID for this topic
        prompt: The user's message
        is_new_topic: If True, creates new session. If False, resumes existing.

    Returns:
        Claude's response text
    """
    system_prompt = load_system_prompt()

    try:
        # Build base command
        base_cmd = ['claude', '--dangerously-skip-permissions']

        # Add system prompt if available
        if system_prompt:
            base_cmd.extend(['--system-prompt', system_prompt])

        if is_new_topic:
            # New topic = new session
            cmd = base_cmd + ['--session-id', session_uuid, '--print', '-p', prompt]
        else:
            # Continue existing topic session
            cmd = base_cmd + ['--resume', session_uuid, '--print', '-p', prompt]

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=120  # 2 minute timeout
        )

        # If resume failed (session not found), try creating new
        if not is_new_topic and ("No conversation found" in result.stdout or "No conversation found" in result.stderr):
            cmd = base_cmd + ['--session-id', session_uuid, '--print', '-p', prompt]
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=120
            )

        if result.returncode == 0:
            return result.stdout.strip()
        else:
            return f"Error: {result.stderr.strip()}"

    except subprocess.TimeoutExpired:
        return "Response timed out"
    except FileNotFoundError:
        return "claude command not found"
    except Exception as e:
        return f"Error: {str(e)}"


def handle_message(event, topic_root_id: str, is_new_topic: bool) -> Optional[str]:
    """
    Main message handler with per-topic fresh context.

    Args:
        event: The Feishu message event
        topic_root_id: The root message ID of the topic (for session UUID)
        is_new_topic: Whether this is a new topic (fresh context) or continuation

    Returns:
        Response text to send, or None if no response needed.
    """
    message = event.message
    content = parse_message_content(message.content)

    # Note: Decision to respond is already made in bot.py
    # This function just processes the message and returns response

    # Get session UUID based on topic root
    session_uuid = get_topic_session_uuid(topic_root_id)

    # Call Claude with just the current message (fresh context per topic)
    response = call_cc(session_uuid, content, is_new_topic=is_new_topic)

    return response
