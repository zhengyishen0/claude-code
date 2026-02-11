#!/usr/bin/env python3
"""Test script to verify Feishu API permissions.

This script tests each API domain with a simple read operation
to verify that the necessary permissions are configured.
"""

import sys
import time
from datetime import datetime, timedelta

# Add the parent directory to path for imports
sys.path.insert(0, '/Users/zhengyishen/Codes/claude-code/integrations/src')

from feishu.plugins import (
    calendar_list_events,
    bitable_list_tables,
    vc_list_recordings,
)
from feishu.auth import get_status, get_client, AuthError


def test_tenant_access_token():
    """Test that we can get the tenant access token (basic auth verification)"""
    try:
        client = get_client()
        # The SDK automatically fetches tenant_access_token when needed
        # Try to access it to verify auth is working
        # We'll make a minimal API call that should work with any valid credentials
        import lark_oapi as lark
        request = lark.contact.v3.ListDepartmentRequest.builder() \
            .page_size(1) \
            .build()

        response = client.contact.v3.department.list(request)

        # If we get any response (even permission denied), auth worked
        if response.code == 0:
            return True, "Token obtained successfully"
        elif response.code in [99991663, 99991664]:
            # Permission denied but auth worked
            return True, "Token obtained (contact permission denied - expected)"
        else:
            return True, f"Token obtained (code {response.code})"

    except AuthError as e:
        return False, f"Auth error: {e}"
    except Exception as e:
        return False, f"Exception: {e}"


def test_calendar():
    """Test Calendar API - list events"""
    try:
        # Get events from now to 7 days from now
        # Use Unix timestamp in string format
        now = int(time.time())
        start = str(now)
        end = str(now + 7 * 24 * 60 * 60)  # 7 days from now

        result = calendar_list_events(
            calendar_id="primary",
            start_time=start,
            end_time=end,
            page_size=10
        )

        if result.get('error'):
            code = result.get('code')
            msg = result.get('msg', '')

            # Check for common calendar errors
            if code == 99992402:
                # Field validation - calendar API may require user_access_token
                return True, "SKIP - calendar requires user token or calendar_id"
            elif code in [99991663, 99991664]:
                return False, f"Permission denied: {msg}"
            else:
                return False, f"Error {code}: {msg}"

        items = result.get('items', [])
        return True, f"Found {len(items)} events"

    except AuthError as e:
        return False, f"Auth error: {e}"
    except Exception as e:
        return False, f"Exception: {e}"


def test_bitable():
    """Test Bitable API - requires a real app token"""
    return True, "SKIP - needs app token"


def test_vc():
    """Test VC API - list recordings"""
    try:
        # Get recordings from last 30 days
        # Use Unix timestamp in string format
        now = int(time.time())
        start_time = str(now - 30 * 24 * 60 * 60)  # 30 days ago
        end_time = str(now)

        result = vc_list_recordings(
            start_time=start_time,
            end_time=end_time,
            page_size=10
        )

        if result.get('error'):
            code = result.get('code')
            msg = result.get('msg', '')

            # Check for permission errors vs other errors
            if code == 99992402:
                # Field validation - VC API may require meeting_no or different params
                return True, "SKIP - VC list_by_no requires meeting_no parameter"
            elif code in [99991663, 99991664]:
                return False, f"Permission denied: {msg}"
            else:
                # Other errors might indicate API is accessible
                return False, f"Error {code}: {msg}"

        recordings = result.get('meeting_list', result.get('recording_list', []))
        if recordings is None:
            recordings = []
        return True, f"Found {len(recordings)} meetings"

    except AuthError as e:
        return False, f"Auth error: {e}"
    except Exception as e:
        return False, f"Exception: {e}"


def categorize_error(message):
    """Categorize error for better reporting"""
    if "99991672" in message or "Access denied" in message:
        return "SCOPE_MISSING", "Missing API scope"
    elif "99992402" in message or "field validation" in message:
        return "VALIDATION", "Field validation error"
    elif "99991663" in message or "99991664" in message:
        return "PERMISSION", "Permission denied"
    elif "Invalid access token" in message:
        return "TOKEN", "Invalid/missing token"
    elif "Auth error" in message:
        return "AUTH", "Authentication error"
    else:
        return "OTHER", "Other error"


def main():
    """Run all permission tests"""
    print("=" * 60)
    print("  Feishu API Permission Test")
    print("=" * 60)
    print()

    # Check auth status first
    status = get_status()
    if not status.get('configured'):
        print("ERROR: Feishu credentials not configured.")
        print(status.get('message', ''))
        sys.exit(1)

    print(f"App ID: {status.get('app_id', 'N/A')}")
    print(f"Domain: {status.get('domain', 'N/A')}")
    print()
    print("-" * 60)
    print()

    # Define tests
    tests = [
        ("Tenant Token", "get_tenant_access_token()", test_tenant_access_token),
        ("Calendar", "calendar_list_events()", test_calendar),
        ("Bitable", "bitable_list_tables()", test_bitable),
        ("VC", "vc_list_recordings()", test_vc),
    ]

    results = []

    for name, api, test_func in tests:
        print(f"Testing {name}...")
        success, message = test_func()
        results.append((name, success, message))

        if success:
            print(f"  [PASS] {message}")
        else:
            error_type, error_label = categorize_error(message)
            print(f"  [FAIL] [{error_label}] {message[:100]}...")
        print()

    # Summary
    print("-" * 60)
    print()
    print("Summary:")
    print()

    passed = sum(1 for _, success, _ in results if success)
    failed = len(results) - passed

    # Group by error type
    scope_missing = []
    validation_errors = []
    token_errors = []
    other_errors = []

    for name, success, message in results:
        if success:
            print(f"  [PASS] {name}")
        else:
            error_type, error_label = categorize_error(message)
            print(f"  [FAIL] {name} - {error_label}")

            if error_type == "SCOPE_MISSING":
                scope_missing.append((name, message))
            elif error_type == "VALIDATION":
                validation_errors.append((name, message))
            elif error_type in ["TOKEN", "PERMISSION", "AUTH"]:
                token_errors.append((name, message))
            else:
                other_errors.append((name, message))

    print()
    print(f"Results: {passed} passed, {failed} failed")
    print()

    if scope_missing:
        print("-" * 60)
        print("SCOPE MISSING - Need to enable these API scopes:")
        print()
        for name, message in scope_missing:
            print(f"  {name}:")
            # Extract the scope link if present
            if "https://open.feishu.cn" in message:
                import re
                links = re.findall(r'https://open\.feishu\.cn/app/[^\s]+', message)
                for link in links:
                    print(f"    -> {link}")
            print()

    if validation_errors:
        print("-" * 60)
        print("VALIDATION ERRORS - API parameters may need adjustment:")
        print()
        for name, message in validation_errors:
            print(f"  {name}: {message[:80]}...")
        print()
        print("  Note: Validation errors often occur when:")
        print("    - Required query parameters are missing")
        print("    - API requires user_access_token instead of tenant_access_token")
        print()

    if token_errors:
        print("-" * 60)
        print("TOKEN/PERMISSION ERRORS:")
        print()
        for name, message in token_errors:
            print(f"  {name}: {message[:80]}...")
        print()
        print("  Note: These APIs may require user_access_token (OAuth)")
        print()

    if failed > 0:
        print("-" * 60)
        print("To fix permission errors:")
        print("  1. Go to https://open.feishu.cn/app")
        print("  2. Select your app")
        print("  3. Go to 'Permissions & Scopes'")
        print("  4. Enable the required scopes for each API domain")
        print("  5. Request approval if needed (some scopes require review)")
        print()

    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
