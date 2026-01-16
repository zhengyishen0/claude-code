"""
Google API Discovery - introspection of available services and methods.

Google publishes machine-readable descriptions of all their APIs via the
Discovery API. This module uses that to dynamically list available methods
and their parameters.

When Google adds new APIs or methods, they automatically become available
here without any code changes.
"""

from typing import Optional
from googleapiclient.discovery import build
import httplib2

from .auth import get_credentials
from .api import SERVICE_VERSIONS


def list_services() -> list[str]:
    """
    List available Google services that we support.

    Returns:
        List of service names
    """
    return list(SERVICE_VERSIONS.keys())


def list_methods(service_name: str) -> list[dict]:
    """
    List all methods available for a Google service.

    Uses Google's Discovery API to fetch the service description,
    which includes all available methods and their parameters.

    Args:
        service_name: 'gmail', 'calendar', 'drive', etc.

    Returns:
        List of dicts with method info:
        [{"name": "users.messages.list", "description": "...", "http_method": "GET"}, ...]
    """
    creds = get_credentials()
    version = SERVICE_VERSIONS.get(service_name, 'v1')
    service = build(service_name, version, credentials=creds)

    methods = []
    _collect_methods(service._resourceDesc, '', methods)

    return sorted(methods, key=lambda m: m['name'])


def _collect_methods(resource_desc: dict, prefix: str, methods: list):
    """
    Recursively collect methods from a discovery document.

    The discovery document has a nested structure:
    {
        "resources": {
            "users": {
                "resources": {
                    "messages": {
                        "methods": {
                            "list": {...},
                            "get": {...}
                        }
                    }
                }
            }
        }
    }

    This function flattens it to: ["users.messages.list", "users.messages.get", ...]
    """
    # Collect methods at this level
    for name, info in resource_desc.get('methods', {}).items():
        full_name = f"{prefix}{name}" if prefix else name
        methods.append({
            "name": full_name,
            "description": info.get('description', ''),
            "http_method": info.get('httpMethod', ''),
        })

    # Recurse into nested resources
    for name, sub_resource in resource_desc.get('resources', {}).items():
        sub_prefix = f"{prefix}{name}." if prefix else f"{name}."
        _collect_methods(sub_resource, sub_prefix, methods)


def get_method_help(service_name: str, method_name: str) -> dict:
    """
    Get detailed information about a specific API method.

    Args:
        service_name: 'gmail', 'calendar', 'drive', etc.
        method_name: 'users.messages.list', 'events.insert', etc.

    Returns:
        Dict with method details including parameters, description, etc.
    """
    creds = get_credentials()
    version = SERVICE_VERSIONS.get(service_name, 'v1')
    service = build(service_name, version, credentials=creds)

    # Navigate to method in discovery doc
    desc = service._resourceDesc
    parts = method_name.split('.')

    # Navigate through resources to find the method
    for part in parts[:-1]:
        resources = desc.get('resources', {})
        if part in resources:
            desc = resources[part]
        else:
            return {"error": f"Resource '{part}' not found in {service_name}"}

    # Get the method info
    method_info = desc.get('methods', {}).get(parts[-1], {})

    if not method_info:
        return {"error": f"Method '{method_name}' not found in {service_name}"}

    # Build parameter info
    parameters = {}
    for name, info in method_info.get('parameters', {}).items():
        parameters[name] = {
            "required": info.get('required', False),
            "type": info.get('type', 'string'),
            "description": info.get('description', ''),
            "default": info.get('default'),
            "enum": info.get('enum'),
            "location": info.get('location', 'query'),
        }

    # Check if method accepts a request body
    request_body = None
    if 'request' in method_info:
        request_body = method_info['request'].get('$ref')

    return {
        "service": service_name,
        "method": method_name,
        "description": method_info.get('description', ''),
        "http_method": method_info.get('httpMethod', ''),
        "path": method_info.get('path', ''),
        "parameters": parameters,
        "request_body": request_body,
        "scopes": method_info.get('scopes', []),
    }


def get_all_google_services() -> list[dict]:
    """
    Fetch ALL available Google services from the Discovery API.

    Note: This returns 200+ services. Most require separate authentication
    and may not be useful for typical use cases.

    Returns:
        List of all Google API services
    """
    import requests

    url = "https://www.googleapis.com/discovery/v1/apis"
    resp = requests.get(url)
    data = resp.json()

    services = []
    for item in data.get('items', []):
        services.append({
            'name': item['name'],
            'version': item['version'],
            'title': item.get('title', ''),
            'description': item.get('description', '')[:200],
        })

    return sorted(services, key=lambda s: s['name'])


# Re-export SERVICE_VERSIONS for convenience
__all__ = ['list_services', 'list_methods', 'get_method_help', 'get_all_google_services', 'SERVICE_VERSIONS']
