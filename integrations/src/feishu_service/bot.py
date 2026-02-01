"""Feishu/Lark Bot WebSocket long connection client

This module provides a WebSocket-based bot listener that receives messages
from Feishu/Lark in real-time using the long connection protocol.

Usage:
    # With default handler (prints messages)
    from feishu_service.bot import start_bot
    start_bot()

    # With custom handler
    from feishu_service.bot import start_bot, create_event_handler

    def my_handler(data):
        message = data.event.message
        print(f"Got message: {message.content}")

    handler = create_event_handler(my_handler)
    start_bot(event_handler=handler)

    # With CC integration (auto-responds via Claude Code)
    from feishu_service.bot import start_bot_with_cc
    start_bot_with_cc()
"""

import json
import time
import sys
from typing import Callable, Optional

import lark_oapi as lark
from lark_oapi.api.im.v1 import P2ImMessageReceiveV1

from .auth import get_credentials, AuthError, CREDENTIALS_PATH
from .api import call_api
from .bot_handler import handle_message, is_bot_mentioned


class BotError(Exception):
    """Bot configuration or runtime error"""
    pass


def send_message(chat_id: str, text: str) -> dict:
    """
    Send a text message to a chat.

    Args:
        chat_id: The chat ID to send the message to
        text: The message text to send

    Returns:
        API response dict
    """
    body = {
        "receive_id": chat_id,
        "msg_type": "text",
        "content": json.dumps({"text": text})
    }
    return call_api("im", "im/v1/messages", {"receive_id_type": "chat_id"}, body)


def default_message_handler(data: P2ImMessageReceiveV1) -> None:
    """
    Default handler that prints received messages.

    Args:
        data: The message receive event data
    """
    try:
        event = data.event
        message = event.message
        sender = event.sender

        # Extract message details
        msg_id = message.message_id
        msg_type = message.message_type
        chat_id = message.chat_id
        content = message.content

        # Extract sender info
        sender_id = sender.sender_id.open_id if sender.sender_id else "unknown"
        sender_type = sender.sender_type

        # Parse content (it's JSON)
        try:
            content_obj = json.loads(content) if content else {}
        except json.JSONDecodeError:
            content_obj = {"raw": content}

        print("\n" + "=" * 60)
        print("  Received Message")
        print("=" * 60)
        print(f"  Message ID: {msg_id}")
        print(f"  Type: {msg_type}")
        print(f"  Chat ID: {chat_id}")
        print(f"  Sender: {sender_id} ({sender_type})")
        print(f"  Content: {json.dumps(content_obj, indent=4, ensure_ascii=False)}")
        print("=" * 60 + "\n")

    except Exception as e:
        print(f"Error processing message: {e}")
        # Print raw data for debugging
        print(f"Raw event data: {data}")


def cc_message_handler(data: P2ImMessageReceiveV1) -> None:
    """
    Message handler that integrates with Claude Code CLI.

    - DM: Always respond
    - Group: Only respond when @mentioned, stores all messages
    - Uses cc --resume for persistent conversations per chat
    - Sends instant "thinking" indicator before processing

    Args:
        data: The message receive event data
    """
    t0 = time.time()
    print(f"\n[TIMING] Message received at {t0:.3f}")

    try:
        event = data.event
        message = event.message
        chat_id = message.chat_id
        chat_type = message.chat_type  # "p2p" for DM, "group" for group

        # Check message create_time vs now
        msg_create_time = int(message.create_time) / 1000  # ms to seconds
        print(f"[TIMING] Message created: {msg_create_time:.3f}, Received: {t0:.3f}, Delay: {(t0 - msg_create_time):.3f}s")

        # Determine if we should respond (DM or @mentioned in group)
        should_respond = chat_type == "p2p" or is_bot_mentioned(event)

        # Send instant "thinking" indicator if we're going to respond
        if should_respond:
            t1 = time.time()
            send_message(chat_id, "🤔")
            t2 = time.time()
            print(f"[TIMING] Sent thinking indicator in {(t2-t1):.3f}s")

        # Process message and get response
        t3 = time.time()
        response = handle_message(event)
        t4 = time.time()
        print(f"[TIMING] Claude processing took {(t4-t3):.3f}s")

        if response:
            # Send response via Feishu API
            t5 = time.time()
            result = send_message(chat_id, response)
            t6 = time.time()
            print(f"[TIMING] Sent response in {(t6-t5):.3f}s")
            print(f"[TIMING] Total end-to-end: {(t6-t0):.3f}s")
            if result.get('error'):
                print(f"Failed to send message: {result.get('msg')}")
            else:
                print(f"Sent response to {chat_id}")
        else:
            print(f"Message stored (no response needed) for {chat_id}")
            print(f"[TIMING] Total (no response): {(time.time()-t0):.3f}s")

    except Exception as e:
        print(f"Error in cc_message_handler: {e}")
        import traceback
        traceback.print_exc()



def create_event_handler(
    message_handler: Callable[[P2ImMessageReceiveV1], None] = None,
    encrypt_key: str = "",
    verification_token: str = "",
) -> lark.EventDispatcherHandler:
    """
    Create an event dispatcher handler with message callback.

    Args:
        message_handler: Callback function for im.message.receive_v1 events.
                        If None, uses default_message_handler.
        encrypt_key: Encryption key from Feishu app config (optional for WS)
        verification_token: Verification token (optional for WS)

    Returns:
        Configured EventDispatcherHandler
    """
    handler = message_handler or default_message_handler

    return lark.EventDispatcherHandler.builder(encrypt_key, verification_token) \
        .register_p2_im_message_receive_v1(handler) \
        .build()


def get_bot_status() -> dict:
    """
    Check if bot is properly configured.

    Returns:
        Dict with configuration status
    """
    if not CREDENTIALS_PATH.exists():
        return {
            "configured": False,
            "message": "Feishu credentials not found. Run 'service feishu admin' first.",
        }

    try:
        creds = get_credentials()
        app_id = creds.get("app_id", "")

        # Check if required fields exist
        if not app_id or not creds.get("app_secret"):
            return {
                "configured": False,
                "message": "Invalid credentials: missing app_id or app_secret",
            }

        return {
            "configured": True,
            "app_id": app_id[:10] + "..." if len(app_id) > 10 else app_id,
            "domain": creds.get("domain", "feishu"),
            "message": "Bot is configured. Use 'service feishu bot start' to start listening.",
            "note": "Ensure 'im:message' event is enabled in Feishu Open Platform console.",
        }

    except Exception as e:
        return {
            "configured": False,
            "error": str(e),
        }


def start_bot(
    event_handler: lark.EventDispatcherHandler = None,
    log_level: lark.LogLevel = lark.LogLevel.INFO,
    auto_reconnect: bool = True,
) -> None:
    """
    Start the WebSocket bot listener.

    This function blocks and listens for incoming messages via WebSocket.

    Args:
        event_handler: Custom event handler. If None, creates one with default_message_handler.
        log_level: Logging level (DEBUG, INFO, WARNING, ERROR)
        auto_reconnect: Whether to auto-reconnect on connection loss

    Raises:
        BotError: If credentials are not configured
        lark.ws.ClientException: If connection fails due to client error
        lark.ws.ServerException: If connection fails due to server error
    """
    # Load credentials
    try:
        creds = get_credentials()
    except AuthError as e:
        raise BotError(f"Bot not configured: {e}")

    app_id = creds.get("app_id")
    app_secret = creds.get("app_secret")
    domain = creds.get("domain", "feishu")

    if not app_id or not app_secret:
        raise BotError("Invalid credentials: missing app_id or app_secret")

    # Set domain URL
    domain_url = lark.LARK_DOMAIN if domain == "lark" else lark.FEISHU_DOMAIN

    # Create event handler if not provided
    if event_handler is None:
        event_handler = create_event_handler()

    print("\n" + "=" * 60)
    print("  Feishu Bot Listener")
    print("=" * 60)
    print(f"  App ID: {app_id[:10]}...")
    print(f"  Domain: {domain} ({domain_url})")
    print(f"  Auto-reconnect: {auto_reconnect}")
    print("=" * 60)
    print("\n  Starting WebSocket connection...")
    print("  Press Ctrl+C to stop.\n")

    # Create WebSocket client
    ws_client = lark.ws.Client(
        app_id=app_id,
        app_secret=app_secret,
        log_level=log_level,
        event_handler=event_handler,
        domain=domain_url,
        auto_reconnect=auto_reconnect,
    )

    try:
        ws_client.start()
    except KeyboardInterrupt:
        print("\n\nBot stopped by user.")
    except Exception as e:
        raise BotError(f"Bot connection failed: {e}")


# CLI integration
def cli_start(verbose: bool = False) -> None:
    """CLI command to start the bot."""
    log_level = lark.LogLevel.DEBUG if verbose else lark.LogLevel.INFO
    try:
        start_bot(log_level=log_level)
    except BotError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Connection error: {e}", file=sys.stderr)
        sys.exit(1)


def cli_status() -> dict:
    """CLI command to check bot status."""
    return get_bot_status()


def start_bot_with_cc(
    log_level: lark.LogLevel = lark.LogLevel.INFO,
    auto_reconnect: bool = True,
) -> None:
    """
    Start the bot with Claude Code integration.

    Messages are processed by cc_message_handler which:
    - Stores all messages in chat history
    - Responds via `cc --resume` for DMs and @mentions
    - Maintains persistent sessions per chat

    Args:
        log_level: Logging level (DEBUG, INFO, WARNING, ERROR)
        auto_reconnect: Whether to auto-reconnect on connection loss
    """
    handler = create_event_handler(message_handler=cc_message_handler)
    print("\n  [CC Mode] Claude Code integration enabled")
    start_bot(event_handler=handler, log_level=log_level, auto_reconnect=auto_reconnect)


def cli_start_cc(verbose: bool = False) -> None:
    """CLI command to start the bot with CC integration."""
    log_level = lark.LogLevel.DEBUG if verbose else lark.LogLevel.INFO
    try:
        start_bot_with_cc(log_level=log_level)
    except BotError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Connection error: {e}", file=sys.stderr)
        sys.exit(1)
