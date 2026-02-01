"""VC (Video Conference) CLI commands.

Get video conference statistics and meeting information.

Actions:
    top_users       Get top users by meeting time
    meeting_stats   Get aggregate meeting statistics

Examples:
    service feishu vc top_users
    service feishu vc top_users days=30 limit=10
    service feishu vc meeting_stats
    service feishu vc meeting_stats days=7
"""

import time
from typing import Any

from ..api import call_api


# Available actions with their descriptions
ACTIONS = {
    'top_users': 'Get top users ranked by total meeting time',
    'meeting_stats': 'Get aggregate meeting statistics (count, duration)',
}


def get_actions() -> dict[str, str]:
    """Return available actions and their descriptions."""
    return ACTIONS


def run_action(action: str, params: dict[str, Any]) -> dict:
    """
    Execute a VC action.

    Args:
        action: Action name (top_users, meeting_stats)
        params: Parameters for the action

    Returns:
        API response as dict

    Raises:
        ValueError: If required parameters are missing
    """
    if action == 'top_users':
        return _top_users(params)
    elif action == 'meeting_stats':
        return _meeting_stats(params)
    else:
        raise ValueError(f"Unknown action: {action}")


def _get_time_range(params: dict) -> tuple[str, str]:
    """Calculate time range based on days parameter."""
    days = int(params.get('days', 30))
    end_time = int(time.time())
    start_time = end_time - (days * 24 * 60 * 60)
    return str(start_time), str(end_time)


def _top_users(params: dict) -> dict:
    """
    Get top users ranked by total meeting time.

    Uses the VC report API to get user meeting statistics.
    """
    start_time, end_time = _get_time_range(params)
    limit = int(params.get('limit', 10))

    # Get user statistics from VC report API
    result = call_api(
        domain='vc',
        method_path='vc/v1/reports/get_top_user',
        params={
            'start_time': start_time,
            'end_time': end_time,
            'limit': limit,
            'order_by': 1,  # Order by meeting duration
        },
    )

    return result


def _meeting_stats(params: dict) -> dict:
    """
    Get aggregate meeting statistics.

    Returns total meetings, total duration, and other metrics.
    """
    start_time, end_time = _get_time_range(params)

    # Get daily statistics
    result = call_api(
        domain='vc',
        method_path='vc/v1/reports/get_daily',
        params={
            'start_time': start_time,
            'end_time': end_time,
        },
    )

    # If we have daily reports, aggregate them
    if 'meeting_report' in result:
        reports = result['meeting_report']
        total_meetings = sum(int(r.get('meeting_count', 0)) for r in reports)
        total_duration = sum(int(r.get('meeting_duration', 0)) for r in reports)
        total_participants = sum(int(r.get('participant_count', 0)) for r in reports)

        return {
            'period_days': int(params.get('days', 30)),
            'total_meetings': total_meetings,
            'total_duration_seconds': total_duration,
            'total_duration_hours': round(total_duration / 3600, 2),
            'total_participants': total_participants,
            'daily_reports': reports,
        }

    return result
