"""Feishu/Lark authentication management"""

import json
from pathlib import Path
from typing import Optional

import lark_oapi as lark


# Configuration paths
CONFIG_DIR = Path.home() / '.config' / 'api' / 'feishu'
CREDENTIALS_PATH = CONFIG_DIR / 'credentials.json'

# Feishu Open Platform URLs
FEISHU_CONSOLE_URL = "https://open.feishu.cn/app"
LARK_CONSOLE_URL = "https://open.larksuite.com/app"


class AuthError(Exception):
    """Authentication error"""
    pass


def get_client() -> lark.Client:
    """
    Get authenticated Feishu client.

    The SDK automatically handles tenant_access_token refresh.

    Returns:
        Authenticated lark.Client

    Raises:
        AuthError: If credentials not found or invalid
    """
    if not CREDENTIALS_PATH.exists():
        raise AuthError(
            "Feishu credentials not found. Run 'service feishu admin' first.\n"
            f"Expected credentials at: {CREDENTIALS_PATH}"
        )

    try:
        data = json.loads(CREDENTIALS_PATH.read_text())
        app_id = data.get('app_id')
        app_secret = data.get('app_secret')
        domain = data.get('domain', 'feishu')  # 'feishu' or 'lark'

        if not app_id or not app_secret:
            raise AuthError("Invalid credentials file: missing app_id or app_secret")

        # Build client with appropriate domain
        builder = lark.Client.builder() \
            .app_id(app_id) \
            .app_secret(app_secret) \
            .log_level(lark.LogLevel.WARNING)

        # Set domain based on configuration
        if domain == 'lark':
            builder = builder.domain(lark.LARK_DOMAIN)
        else:
            builder = builder.domain(lark.FEISHU_DOMAIN)

        return builder.build()

    except json.JSONDecodeError as e:
        raise AuthError(f"Invalid credentials file: {e}")
    except Exception as e:
        raise AuthError(f"Failed to create client: {e}")


def get_credentials() -> dict:
    """
    Load credentials from file.

    Returns:
        Dict with app_id, app_secret, domain

    Raises:
        AuthError: If credentials not found
    """
    if not CREDENTIALS_PATH.exists():
        raise AuthError("Credentials not found. Run 'service feishu admin' first.")

    return json.loads(CREDENTIALS_PATH.read_text())


def save_credentials(app_id: str, app_secret: str, domain: str = 'feishu') -> None:
    """
    Save credentials to file.

    Args:
        app_id: Feishu App ID
        app_secret: Feishu App Secret
        domain: 'feishu' for China or 'lark' for international
    """
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)

    credentials = {
        'app_id': app_id,
        'app_secret': app_secret,
        'domain': domain,
    }

    CREDENTIALS_PATH.write_text(json.dumps(credentials, indent=2))


def verify_credentials() -> dict:
    """
    Verify credentials by making a test API call.

    Returns:
        Dict with verification result

    Raises:
        AuthError: If verification fails
    """
    client = get_client()

    try:
        # Try to list departments - a simple call to verify credentials
        request = lark.contact.v3.ListDepartmentRequest.builder() \
            .page_size(1) \
            .build()

        response = client.contact.v3.department.list(request)

        if response.success():
            return {
                'valid': True,
                'message': 'Credentials verified successfully'
            }
        else:
            # Even if the API call fails due to permissions, credentials are valid
            # if we got a proper error code (not auth error)
            if response.code in [99991663, 99991664]:  # Permission denied codes
                return {
                    'valid': True,
                    'message': 'Credentials valid (API permissions may need configuration)',
                    'note': response.msg
                }
            else:
                return {
                    'valid': False,
                    'message': f'Verification failed: {response.msg}',
                    'code': response.code
                }

    except Exception as e:
        raise AuthError(f"Verification failed: {e}")


def get_status() -> dict:
    """
    Get current authentication status.

    Returns:
        Dict with auth info
    """
    if not CREDENTIALS_PATH.exists():
        return {
            'configured': False,
            'message': "Not configured. Run 'service feishu admin' to set up."
        }

    try:
        creds = get_credentials()
        return {
            'configured': True,
            'app_id': creds.get('app_id', '')[:10] + '...',  # Partial for security
            'domain': creds.get('domain', 'feishu'),
            'credentials_path': str(CREDENTIALS_PATH),
        }
    except Exception as e:
        return {
            'configured': False,
            'error': str(e)
        }


def revoke_credentials() -> bool:
    """
    Remove stored credentials.

    Returns:
        True if credentials were deleted
    """
    if CREDENTIALS_PATH.exists():
        CREDENTIALS_PATH.unlink()
        return True
    return False


def setup_interactive() -> bool:
    """
    Interactive setup for Feishu credentials.

    Returns:
        True if setup successful
    """
    print("\n" + "=" * 60)
    print("  Feishu/Lark API Setup")
    print("=" * 60)
    print()
    print("  Step 1: Choose your platform")
    print()
    print("    [1] Feishu - China")
    print("    [2] Lark - International")
    print()

    try:
        choice = input("  Enter 1 or 2 [1]: ").strip() or '1'
    except KeyboardInterrupt:
        print("\n\nSetup cancelled.")
        return False

    if choice == '2':
        domain = 'lark'
        console_url = LARK_CONSOLE_URL
        platform_name = "Lark"
    else:
        domain = 'feishu'
        console_url = FEISHU_CONSOLE_URL
        platform_name = "Feishu"

    print()
    print("-" * 60)
    print(f"  Step 2: Create an app on {platform_name} Open Platform")
    print("-" * 60)
    print()
    print(f"  1. Open: {console_url}")
    print()
    print("  2. Click 'Create Custom App'")
    print()
    print("  3. Fill in:")
    print("     - App Name: e.g., 'My API Client'")
    print("     - App Description: e.g., 'API integration'")
    print()
    print("  4. After creation, go to 'Credentials & Basic Info'")
    print()
    print("  5. Copy the App ID and App Secret")
    print()
    print("-" * 60)

    try:
        print()
        app_id = input("  App ID: ").strip()
        if not app_id:
            print("\n  App ID is required.")
            return False

        app_secret = input("  App Secret: ").strip()
        if not app_secret:
            print("\n  App Secret is required.")
            return False

    except KeyboardInterrupt:
        print("\n\nSetup cancelled.")
        return False

    # Save credentials
    save_credentials(app_id, app_secret, domain)

    print()
    print("  Verifying credentials...")

    try:
        result = verify_credentials()
        if result.get('valid'):
            print(f"  + {result.get('message')}")
            if result.get('note'):
                print(f"    Note: {result.get('note')}")
        else:
            print(f"  ! {result.get('message')}")
            print("    Credentials saved, but verification returned an error.")
            print("    This may be normal if API permissions are not yet configured.")
    except AuthError as e:
        print(f"  ! Could not verify: {e}")
        print("    Credentials saved anyway. Check App ID and Secret if you have issues.")

    return True
