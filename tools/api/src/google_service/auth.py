"""Google OAuth authentication management"""

import json
import sys
from pathlib import Path
from typing import Optional

from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request
from google_auth_oauthlib.flow import InstalledAppFlow


# Configuration paths
CONFIG_DIR = Path.home() / '.config' / 'api' / 'google'
TOKEN_PATH = CONFIG_DIR / 'token.json'
CLIENT_SECRET_PATH = CONFIG_DIR / 'client_secret.json'

# Google Cloud Console URL for creating OAuth credentials
CONSOLE_URL = "https://console.cloud.google.com/apis/credentials"

# Available OAuth scopes
SCOPES = {
    'gmail':    'https://www.googleapis.com/auth/gmail.modify',
    'calendar': 'https://www.googleapis.com/auth/calendar',
    'drive':    'https://www.googleapis.com/auth/drive',
    'sheets':   'https://www.googleapis.com/auth/spreadsheets',
    'docs':     'https://www.googleapis.com/auth/documents',
    'contacts': 'https://www.googleapis.com/auth/contacts',
    'tasks':    'https://www.googleapis.com/auth/tasks',
}


class AuthError(Exception):
    """Authentication error"""
    pass


def get_credentials() -> Credentials:
    """
    Load credentials from token file, auto-refresh if expired.

    Returns:
        Valid Google credentials

    Raises:
        AuthError: If not authorized or refresh fails
    """
    if not TOKEN_PATH.exists():
        raise AuthError("Not authorized. Run 'api google auth' first.")

    try:
        creds = Credentials.from_authorized_user_file(str(TOKEN_PATH))
    except Exception as e:
        raise AuthError(f"Failed to load credentials: {e}")

    # Auto-refresh if expired
    if creds.expired and creds.refresh_token:
        try:
            creds.refresh(Request())
            # Save refreshed token
            TOKEN_PATH.write_text(creds.to_json())
        except Exception as e:
            raise AuthError(f"Failed to refresh token: {e}. Run 'api google auth' again.")

    if not creds.valid:
        raise AuthError("Invalid credentials. Run 'api google auth' again.")

    return creds


def setup_client_secret_interactive() -> bool:
    """
    Interactive setup for client_secret.json.
    Prompts user to create OAuth credentials and paste the JSON.

    Returns:
        True if setup successful, False if user cancelled
    """
    print("\n" + "=" * 60)
    print("  Google API Setup - One-time configuration")
    print("=" * 60)
    print()
    print("  Step 1: Click this link to open Google Cloud Console:")
    print()
    print(f"    → {CONSOLE_URL}")
    print()
    print("  Step 2: In the console:")
    print("    1. Create a project (if you don't have one)")
    print("    2. Click '+ CREATE CREDENTIALS' → 'OAuth client ID'")
    print("    3. If asked, configure consent screen (External, just your email)")
    print("    4. Application type: 'Desktop app'")
    print("    5. Click 'Create'")
    print("    6. Click 'DOWNLOAD JSON'")
    print()
    print("  Step 3: Open the downloaded file and copy ALL its content")
    print()
    print("-" * 60)
    print("  Paste the JSON content below (then press Enter twice):")
    print("-" * 60)

    # Read multiline input until empty line
    lines = []
    try:
        while True:
            line = input()
            if line == "" and lines:
                break
            lines.append(line)
    except EOFError:
        pass
    except KeyboardInterrupt:
        print("\n\nSetup cancelled.")
        return False

    json_content = "\n".join(lines).strip()

    if not json_content:
        print("\nNo content provided. Setup cancelled.")
        return False

    # Validate JSON
    try:
        data = json.loads(json_content)
        # Check for required fields
        if 'installed' not in data and 'web' not in data:
            print("\n❌ Invalid OAuth client JSON. Missing 'installed' or 'web' key.")
            print("   Make sure you downloaded the OAuth client JSON, not a service account key.")
            return False
    except json.JSONDecodeError as e:
        print(f"\n❌ Invalid JSON format: {e}")
        return False

    # Save the file
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CLIENT_SECRET_PATH.write_text(json_content)
    print(f"\n✅ Credentials saved to {CLIENT_SECRET_PATH}")
    return True


def authorize(scopes: Optional[list[str]] = None, interactive: bool = True) -> Credentials:
    """
    Run OAuth flow to authorize Google account.

    If client_secret.json doesn't exist and interactive=True,
    will guide user through setup process.

    Args:
        scopes: List of scope names (gmail, calendar, etc.)
                If None, requests all available scopes.
        interactive: If True, prompt user to set up credentials if missing

    Returns:
        Authorized credentials

    Raises:
        AuthError: If setup fails or user cancels
    """
    # Check if client_secret.json exists
    if not CLIENT_SECRET_PATH.exists():
        if interactive:
            if not setup_client_secret_interactive():
                raise AuthError("Setup cancelled. Run 'api google auth' to try again.")
        else:
            raise AuthError(
                f"OAuth client secret not found at {CLIENT_SECRET_PATH}\n"
                "Run 'api google auth' to set up."
            )

    # Convert scope names to URLs
    if scopes:
        scope_urls = []
        for s in scopes:
            s = s.strip().lower()
            if s in SCOPES:
                scope_urls.append(SCOPES[s])
            else:
                raise ValueError(f"Unknown scope: {s}. Available: {', '.join(SCOPES.keys())}")
    else:
        scope_urls = list(SCOPES.values())

    # Run OAuth flow
    print("\n" + "=" * 60)
    print("  Browser Authorization")
    print("=" * 60)
    print()
    print("  Opening your browser...")
    print("  → Sign in to Google")
    print("  → Click 'Allow' to grant access")
    print()

    flow = InstalledAppFlow.from_client_secrets_file(
        str(CLIENT_SECRET_PATH),
        scope_urls
    )
    creds = flow.run_local_server(port=0)

    # Save credentials
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    TOKEN_PATH.write_text(creds.to_json())

    return creds


def get_status() -> dict:
    """
    Get current authorization status.

    Returns:
        Dict with authorization info
    """
    if not TOKEN_PATH.exists():
        return {
            "authorized": False,
            "message": "Not authorized. Run 'api google auth' to authorize."
        }

    try:
        creds = Credentials.from_authorized_user_file(str(TOKEN_PATH))

        # Parse scope URLs back to names
        scope_names = []
        if creds.scopes:
            scope_url_to_name = {v: k for k, v in SCOPES.items()}
            for scope_url in creds.scopes:
                name = scope_url_to_name.get(scope_url, scope_url)
                scope_names.append(name)

        return {
            "authorized": True,
            "valid": creds.valid,
            "expired": creds.expired,
            "scopes": scope_names,
            "token_path": str(TOKEN_PATH),
            "can_refresh": bool(creds.refresh_token),
        }
    except Exception as e:
        return {
            "authorized": False,
            "error": str(e),
            "message": "Token file exists but is invalid. Run 'api google auth' again."
        }


def revoke_auth() -> bool:
    """
    Revoke authorization by deleting token file.

    Returns:
        True if token was deleted, False if no token existed
    """
    if TOKEN_PATH.exists():
        TOKEN_PATH.unlink()
        return True
    return False
