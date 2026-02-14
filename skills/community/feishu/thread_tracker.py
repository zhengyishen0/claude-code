"""Thread tracking for Feishu bot conversations.

Stores thread metadata to allow listing and resuming past conversations.
Thread data is stored in a JSON file in the Feishu config directory.

Usage:
    from feishu.thread_tracker import track_thread, list_threads, get_thread

    # Track a new or updated thread
    track_thread(
        thread_id="om_xxx",
        chat_id="oc_xxx",
        chat_type="p2p",
        title="First message text"
    )

    # List all tracked threads
    threads = list_threads(limit=20)

    # Get a specific thread
    thread = get_thread("om_xxx")
"""

import json
import os
import time
from pathlib import Path
from typing import Optional


# Default storage location (same directory as credentials)
DEFAULT_THREADS_PATH = Path.home() / '.config' / 'api' / 'feishu' / 'threads.json'

# Environment variable to override the path
THREADS_PATH_ENV = 'FEISHU_THREADS_PATH'


def _get_threads_path() -> Path:
    """Get the path to the threads file, respecting environment override."""
    env_path = os.environ.get(THREADS_PATH_ENV)
    if env_path:
        return Path(env_path)
    return DEFAULT_THREADS_PATH


def _load_threads() -> dict:
    """Load threads from the JSON file."""
    path = _get_threads_path()
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text())
    except (json.JSONDecodeError, IOError):
        return {}


def _save_threads(threads: dict) -> None:
    """Save threads to the JSON file."""
    path = _get_threads_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(threads, indent=2, ensure_ascii=False))


def track_thread(
    thread_id: str,
    chat_id: str,
    chat_type: str = "p2p",
    title: Optional[str] = None,
    sender_id: Optional[str] = None,
) -> dict:
    """
    Track a thread (create or update).

    Args:
        thread_id: The root message ID of the thread (om_xxx format)
        chat_id: The chat ID where the thread exists (oc_xxx format)
        chat_type: Type of chat - "p2p" for DM, "group" for group chat
        title: Optional title/summary for the thread (e.g., first message text)
        sender_id: Optional open_id of the user who started the thread

    Returns:
        The thread record that was created/updated
    """
    threads = _load_threads()
    now = time.time()

    if thread_id in threads:
        # Update existing thread
        thread = threads[thread_id]
        thread['last_activity'] = now
        thread['message_count'] = thread.get('message_count', 1) + 1
        # Update title if provided and not already set
        if title and not thread.get('title'):
            thread['title'] = title[:100]  # Truncate long titles
    else:
        # Create new thread
        thread = {
            'thread_id': thread_id,
            'chat_id': chat_id,
            'chat_type': chat_type,
            'created_at': now,
            'last_activity': now,
            'message_count': 1,
        }
        if title:
            thread['title'] = title[:100]
        if sender_id:
            thread['sender_id'] = sender_id

    threads[thread_id] = thread
    _save_threads(threads)
    return thread


def get_thread(thread_id: str) -> Optional[dict]:
    """
    Get a specific thread by ID.

    Args:
        thread_id: The thread ID (root message ID)

    Returns:
        Thread record dict or None if not found
    """
    threads = _load_threads()
    return threads.get(thread_id)


def list_threads(
    limit: int = 20,
    chat_id: Optional[str] = None,
    chat_type: Optional[str] = None,
) -> list[dict]:
    """
    List tracked threads, sorted by last activity (most recent first).

    Args:
        limit: Maximum number of threads to return
        chat_id: Filter by chat ID
        chat_type: Filter by chat type ("p2p" or "group")

    Returns:
        List of thread records
    """
    threads = _load_threads()

    # Convert to list
    thread_list = list(threads.values())

    # Apply filters
    if chat_id:
        thread_list = [t for t in thread_list if t.get('chat_id') == chat_id]
    if chat_type:
        thread_list = [t for t in thread_list if t.get('chat_type') == chat_type]

    # Sort by last activity (most recent first)
    thread_list.sort(key=lambda t: t.get('last_activity', 0), reverse=True)

    # Apply limit
    return thread_list[:limit]


def delete_thread(thread_id: str) -> bool:
    """
    Delete a tracked thread.

    Args:
        thread_id: The thread ID to delete

    Returns:
        True if thread was deleted, False if not found
    """
    threads = _load_threads()
    if thread_id in threads:
        del threads[thread_id]
        _save_threads(threads)
        return True
    return False


def clear_old_threads(max_age_days: int = 30) -> int:
    """
    Remove threads older than the specified age.

    Args:
        max_age_days: Remove threads with no activity for this many days

    Returns:
        Number of threads removed
    """
    threads = _load_threads()
    cutoff = time.time() - (max_age_days * 24 * 60 * 60)

    old_threads = [
        tid for tid, t in threads.items()
        if t.get('last_activity', 0) < cutoff
    ]

    for tid in old_threads:
        del threads[tid]

    if old_threads:
        _save_threads(threads)

    return len(old_threads)


def get_threads_path() -> str:
    """Get the current threads file path as a string."""
    return str(_get_threads_path())
