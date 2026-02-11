"""Core Feishu API caller - generic interface for all Feishu APIs"""

import json
from typing import Optional, Any
import lark_oapi as lark

from .auth import get_client, AuthError


# Service domains and their API versions
# Format: domain -> {resource -> version}
SERVICE_DOMAINS = {
    'im': {
        'description': 'Instant Messaging - messages, chats, groups',
        'version': 'v1',
    },
    'contact': {
        'description': 'Contacts - users, departments, groups',
        'version': 'v3',
    },
    'calendar': {
        'description': 'Calendar - events, calendars, attendees',
        'version': 'v4',
    },
    'drive': {
        'description': 'Drive - files, folders, permissions',
        'version': 'v1',
    },
    'docx': {
        'description': 'Documents - create, read document content',
        'version': 'v1',
    },
    'sheets': {
        'description': 'Sheets - spreadsheets, cells, ranges',
        'version': 'v3',
    },
    'bitable': {
        'description': 'Bitable - tables, records, fields (like Airtable)',
        'version': 'v1',
    },
    'wiki': {
        'description': 'Wiki - knowledge base, spaces, nodes',
        'version': 'v2',
    },
    'approval': {
        'description': 'Approval - workflows, instances, tasks',
        'version': 'v4',
    },
    'attendance': {
        'description': 'Attendance - check-ins, shifts, leave',
        'version': 'v1',
    },
    'task': {
        'description': 'Tasks - task management',
        'version': 'v2',
    },
    'mail': {
        'description': 'Mail - mailboxes, messages (enterprise)',
        'version': 'v1',
    },
    'vc': {
        'description': 'Video Conference - meetings, rooms',
        'version': 'v1',
    },
    'search': {
        'description': 'Search - unified search across Feishu',
        'version': 'v2',
    },
    'baike': {
        'description': 'Baike - enterprise glossary/wiki',
        'version': 'v1',
    },
    'application': {
        'description': 'Application - app management, visibility',
        'version': 'v6',
    },
}


def call_api_with_method(
    http_method: str,
    method_path: str,
    params: Optional[dict] = None,
    body: Optional[dict] = None,
) -> dict:
    """
    Call Feishu API with explicit HTTP method.

    Args:
        http_method: HTTP method (GET, POST, PUT, PATCH, DELETE)
        method_path: API path like 'im/v1/messages/om_xxx'
        params: Query parameters
        body: Request body

    Returns:
        API response as dict
    """
    client = get_client()

    # Map string to HttpMethod enum
    method_map = {
        'GET': lark.HttpMethod.GET,
        'POST': lark.HttpMethod.POST,
        'PUT': lark.HttpMethod.PUT,
        'PATCH': lark.HttpMethod.PATCH,
        'DELETE': lark.HttpMethod.DELETE,
    }
    method = method_map.get(http_method.upper(), lark.HttpMethod.GET)

    # Build the full URI
    uri = f"/open-apis/{method_path}"

    # Build query parameters
    queries = []
    if params:
        for k, v in params.items():
            if v is not None:
                queries.append((k, str(v)))

    # Build request
    request_builder = lark.BaseRequest.builder() \
        .http_method(method) \
        .uri(uri) \
        .token_types({lark.AccessTokenType.TENANT})

    if queries:
        request_builder = request_builder.queries(queries)

    if body:
        request_builder = request_builder.body(body)

    request = request_builder.build()

    # Execute request
    response: lark.BaseResponse = client.request(request)

    # Handle response
    if response.success():
        if response.raw and response.raw.content:
            data = json.loads(response.raw.content)
            return data.get('data', {'success': True})
        return {'success': True}
    else:
        return {
            'error': True,
            'code': response.code,
            'msg': response.msg,
            'log_id': response.get_log_id(),
        }


def call_api(
    domain: str,
    method_path: str,
    params: Optional[dict] = None,
    body: Optional[dict] = None,
) -> dict:
    """
    Generic Feishu API caller using raw request interface.

    This allows calling any Feishu API by constructing the request manually,
    similar to how the Google integration works.

    Args:
        domain: API domain (im, contact, calendar, drive, etc.)
        method_path: API path like 'message.create' or 'user.get'
        params: Query parameters
        body: Request body for POST/PUT/PATCH

    Returns:
        API response as dict

    Examples:
        # Send a message
        call_api('im', 'v1/messages',
                 params={'receive_id_type': 'chat_id'},
                 body={'receive_id': 'oc_xxx', 'msg_type': 'text', 'content': '{"text":"Hello"}'})

        # List calendar events
        call_api('calendar', 'v4/calendars/primary/events',
                 params={'page_size': 10})

        # Get user info
        call_api('contact', 'v3/users/:user_id',
                 params={'user_id': 'xxx', 'user_id_type': 'open_id'})
    """
    client = get_client()

    # Determine HTTP method based on path pattern
    http_method = _infer_http_method(method_path, body)

    # Build the full URI
    uri = f"/open-apis/{method_path}"

    # Build query parameters
    queries = []
    if params:
        for k, v in params.items():
            if v is not None:
                queries.append((k, str(v)))

    # Build request
    request_builder = lark.BaseRequest.builder() \
        .http_method(http_method) \
        .uri(uri) \
        .token_types({lark.AccessTokenType.TENANT})

    if queries:
        request_builder = request_builder.queries(queries)

    if body:
        request_builder = request_builder.body(body)

    request = request_builder.build()

    # Execute request
    response: lark.BaseResponse = client.request(request)

    # Handle response
    if response.success():
        # Parse the actual response from raw.content
        if response.raw and response.raw.content:
            data = json.loads(response.raw.content)
            return data.get('data', {'success': True})
        return {'success': True}
    else:
        return {
            'error': True,
            'code': response.code,
            'msg': response.msg,
            'log_id': response.get_log_id(),
        }


def call_api_semantic(
    domain: str,
    resource: str,
    method: str,
    request_builder_func: callable,
) -> dict:
    """
    Call Feishu API using semantic SDK methods.

    This uses the typed SDK interface for better type safety.

    Args:
        domain: API domain (im, contact, calendar, etc.)
        resource: Resource name (message, user, event, etc.)
        method: Method name (create, get, list, update, delete)
        request_builder_func: Function that builds the request object

    Returns:
        API response as dict

    Example:
        # List users
        call_api_semantic('contact', 'user', 'list',
            lambda: lark.contact.v3.ListUserRequest.builder()
                .page_size(10)
                .build()
        )
    """
    client = get_client()

    # Get the domain module
    domain_module = getattr(lark, domain, None)
    if not domain_module:
        return {'error': True, 'msg': f'Unknown domain: {domain}'}

    # Navigate to resource and method
    # e.g., client.contact.v3.user.list(request)
    try:
        version = SERVICE_DOMAINS.get(domain, {}).get('version', 'v1')
        version_module = getattr(domain_module, version)

        # Build request
        request = request_builder_func()

        # Get the resource handler from client
        client_domain = getattr(client, domain)
        client_version = getattr(client_domain, version)
        client_resource = getattr(client_version, resource)
        client_method = getattr(client_resource, method)

        # Execute
        response = client_method(request)

        if response.success():
            # Convert response data to dict
            if hasattr(response, 'data') and response.data:
                return _response_to_dict(response.data)
            return {'success': True}
        else:
            return {
                'error': True,
                'code': response.code,
                'msg': response.msg,
            }

    except AttributeError as e:
        return {'error': True, 'msg': f'API navigation error: {e}'}
    except Exception as e:
        return {'error': True, 'msg': str(e)}


def list_domains() -> list[dict]:
    """
    List available API domains.

    Returns:
        List of domain info dicts
    """
    return [
        {
            'name': name,
            'version': info['version'],
            'description': info['description'],
        }
        for name, info in sorted(SERVICE_DOMAINS.items())
    ]


def _infer_http_method(path: str, body: Optional[dict]) -> lark.HttpMethod:
    """
    Infer HTTP method from path and body.

    - Paths ending with 'create', 'send', 'batch' + body → POST
    - Paths ending with 'delete' → DELETE
    - Paths ending with 'update', 'patch' → PATCH/PUT
    - Otherwise → GET
    """
    path_lower = path.lower()

    if body:
        # Has body - likely POST, PUT, or PATCH
        if 'delete' in path_lower:
            return lark.HttpMethod.DELETE
        elif 'update' in path_lower or 'patch' in path_lower:
            return lark.HttpMethod.PATCH
        else:
            return lark.HttpMethod.POST
    else:
        # No body
        if 'delete' in path_lower:
            return lark.HttpMethod.DELETE
        else:
            return lark.HttpMethod.GET


def _response_to_dict(obj: Any) -> Any:
    """
    Convert SDK response object to dict recursively.
    """
    if obj is None:
        return None
    elif isinstance(obj, (str, int, float, bool)):
        return obj
    elif isinstance(obj, list):
        return [_response_to_dict(item) for item in obj]
    elif isinstance(obj, dict):
        return {k: _response_to_dict(v) for k, v in obj.items()}
    elif hasattr(obj, '__dict__'):
        # SDK object - convert to dict
        result = {}
        for key, value in obj.__dict__.items():
            if not key.startswith('_'):
                result[key] = _response_to_dict(value)
        return result
    else:
        return str(obj)
