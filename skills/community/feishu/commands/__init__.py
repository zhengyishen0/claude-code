"""Feishu CLI command modules.

This package contains high-level CLI commands for Feishu APIs:
- bitable: Database tables and records (like Airtable)
- im: Instant messaging - send messages, manage chats
- calendar: Calendar events management
- vc: Video conference statistics
"""

from . import bitable
from . import im
from . import calendar
from . import vc

__all__ = ['bitable', 'im', 'calendar', 'vc']
