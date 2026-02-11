"""Core Google API caller - the magic that makes generic API calls possible"""

from typing import Optional
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseDownload
import io

from .auth import get_credentials


# Service name → API version mapping
SERVICE_VERSIONS = {
    'gmail':      'v1',
    'calendar':   'v3',
    'drive':      'v3',
    'sheets':     'v4',
    'docs':       'v1',
    'people':     'v1',   # Contacts API
    'tasks':      'v1',
    'slides':     'v1',
    'youtube':    'v3',
    'workspace':  'directory_v1',  # Google Workspace Admin (renamed from 'admin')
}


def call_api(
    service_name: str,
    resource_method: str,
    params: dict,
    body: Optional[dict] = None
) -> dict:
    """
    Generic Google API caller.

    Args:
        service_name: 'gmail', 'calendar', 'drive', etc.
        resource_method: 'users.messages.list', 'events.insert', etc.
        params: URL parameters (userId=me, maxResults=10, etc.)
        body: Request body for POST/PUT methods

    Returns:
        API response as dict

    Examples:
        call_api('gmail', 'users.messages.list', {'userId': 'me', 'q': 'is:unread'})
        call_api('calendar', 'events.insert', {'calendarId': 'primary'}, body={...})
    """
    # Build service
    creds = get_credentials()
    version = SERVICE_VERSIONS.get(service_name, 'v1')
    service = build(service_name, version, credentials=creds)

    # Navigate to method: "users.messages.list" → service.users().messages().list
    method = _navigate_to_method(service, resource_method)

    # Add body if provided
    if body:
        params['body'] = body

    # Execute and return
    return method(**params).execute()


def call_api_media(
    service_name: str,
    resource_method: str,
    params: dict
) -> bytes:
    """
    Call API method that returns binary data (e.g., drive.files.export).

    Args:
        service_name: 'gmail', 'calendar', 'drive', etc.
        resource_method: Method that returns media (e.g., 'files.export')
        params: URL parameters

    Returns:
        Binary content
    """
    creds = get_credentials()
    version = SERVICE_VERSIONS.get(service_name, 'v1')
    service = build(service_name, version, credentials=creds)

    method = _navigate_to_method(service, resource_method)
    request = method(**params)

    # For export, we can use execute() directly
    if 'export' in resource_method:
        return request.execute()

    # For media download, use MediaIoBaseDownload
    fh = io.BytesIO()
    downloader = MediaIoBaseDownload(fh, request)
    done = False
    while not done:
        _, done = downloader.next_chunk()

    return fh.getvalue()


def _navigate_to_method(service, resource_method: str):
    """
    Navigate service object to reach the target method.

    This is the magic that makes generic API calls possible:
        'users.messages.list' → service.users().messages().list
        'events.insert'       → service.events().insert
        'files.list'          → service.files().list

    Args:
        service: Google API service object
        resource_method: Dot-separated path to method

    Returns:
        The method (callable)
    """
    parts = resource_method.split('.')
    obj = service

    # Navigate through resources (all but last part)
    # Each resource is a method that returns a resource object
    for part in parts[:-1]:
        obj = getattr(obj, part)()

    # Get the final method (don't call it yet, just return the callable)
    method = getattr(obj, parts[-1])

    return method


def get_service(service_name: str):
    """
    Get a Google API service object for direct use.

    This is useful if you need to do something not covered by call_api,
    or for performance when making many calls to the same service.

    Args:
        service_name: 'gmail', 'calendar', 'drive', etc.

    Returns:
        Google API service object
    """
    creds = get_credentials()
    version = SERVICE_VERSIONS.get(service_name, 'v1')
    return build(service_name, version, credentials=creds)
