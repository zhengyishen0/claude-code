"""
Universal API Response Cleaner

Removes noisy/useless data from API responses based on patterns
defined in noise_patterns.yaml.

Works with any JSON response from any API service.
"""

import re
import yaml
import base64
from pathlib import Path
from typing import Any


# Load patterns from yaml file
PATTERNS_FILE = Path(__file__).parent / 'noise_patterns.yaml'

_patterns_cache = None


def load_patterns() -> dict:
    """Load noise patterns from yaml file (cached)"""
    global _patterns_cache

    if _patterns_cache is not None:
        return _patterns_cache

    if not PATTERNS_FILE.exists():
        _patterns_cache = {'key_patterns': [], 'value_patterns': []}
        return _patterns_cache

    with open(PATTERNS_FILE) as f:
        data = yaml.safe_load(f)

    _patterns_cache = {
        'key_patterns': [re.compile(p, re.IGNORECASE) for p in (data.get('key_patterns') or [])],
        'value_patterns': [re.compile(p) for p in (data.get('value_patterns') or [])],
    }

    return _patterns_cache


def is_noise_key(key: str) -> bool:
    """Check if a key matches any noise pattern"""
    patterns = load_patterns()
    return any(p.search(key) for p in patterns['key_patterns'])


def is_noise_value(value: Any) -> bool:
    """Check if a value matches any noise pattern"""
    if not isinstance(value, str):
        return False

    patterns = load_patterns()
    return any(p.search(value) for p in patterns['value_patterns'])


def clean_response(data: Any) -> Any:
    """
    Recursively remove noise from API response.

    Also decodes Gmail email bodies from base64 to readable text.

    Args:
        data: Any JSON-serializable data (dict, list, or primitive)

    Returns:
        Cleaned data with noise removed and email bodies decoded
    """
    # First, handle Gmail message decoding at the top level
    if is_gmail_message(data):
        data = dict(data)  # Make a copy
        data['payload'] = decode_email_body(data['payload'])

    if isinstance(data, dict):
        # Special case: Gmail-style header {name: "X-...", value: "..."}
        if 'name' in data and 'value' in data and len(data) <= 2:
            if is_noise_key(data['name']) or is_noise_value(data.get('value', '')):
                return None  # Mark for removal

        cleaned = {}
        for k, v in data.items():
            # Skip noise keys
            if is_noise_key(k):
                continue
            # Skip noise values
            if is_noise_value(v):
                continue
            # Recurse
            cleaned_v = clean_response(v)
            if cleaned_v is not None:  # Skip items marked for removal
                cleaned[k] = cleaned_v
        return cleaned

    elif isinstance(data, list):
        # Filter out None (items marked for removal) and recurse
        cleaned = [clean_response(item) for item in data]
        return [item for item in cleaned if item is not None]

    else:
        return data


def clean_headers(headers: list[dict]) -> list[dict]:
    """
    Special cleaner for email headers format.

    Gmail returns headers as: [{"name": "From", "value": "..."}, ...]
    This filters out noise headers by name.

    Args:
        headers: List of {name, value} dicts

    Returns:
        Filtered list with noise headers removed
    """
    return [
        h for h in headers
        if not is_noise_key(h.get('name', '')) and not is_noise_value(h.get('value', ''))
    ]


def reload_patterns():
    """Force reload of patterns (useful after editing yaml file)"""
    global _patterns_cache
    _patterns_cache = None
    load_patterns()


def decode_base64url(data: str) -> str:
    """Decode base64url encoded string (Gmail format)"""
    try:
        # Gmail uses URL-safe base64
        decoded = base64.urlsafe_b64decode(data).decode('utf-8')
        return decoded
    except Exception:
        return data  # Return original if decode fails


def decode_email_body(payload: dict) -> dict:
    """
    Decode Gmail email body from base64 to readable text.

    Gmail API returns body content as base64url encoded. This decodes it
    and simplifies the structure for readability.

    Args:
        payload: Gmail message payload dict

    Returns:
        Modified payload with decoded body content
    """
    if not isinstance(payload, dict):
        return payload

    # Helper to extract body from nested parts
    def find_body(p, mime_type):
        if p.get('mimeType') == mime_type:
            body_data = p.get('body', {}).get('data')
            if body_data:
                return decode_base64url(body_data)
        for part in p.get('parts', []):
            result = find_body(part, mime_type)
            if result:
                return result
        return None

    # Try to get plain text first, fall back to HTML
    plain_text = find_body(payload, 'text/plain')
    html_text = find_body(payload, 'text/html')

    # Also check direct body (for simple emails without parts)
    if not plain_text and not html_text:
        body_data = payload.get('body', {}).get('data')
        if body_data:
            decoded = decode_base64url(body_data)
            # Simple heuristic: if it looks like HTML, mark it as such
            if decoded.strip().startswith('<!') or '<html' in decoded.lower():
                html_text = decoded
            else:
                plain_text = decoded

    # Add decoded content to payload
    if plain_text:
        payload['decodedBody'] = plain_text
        payload['bodyType'] = 'text/plain'
    elif html_text:
        # Strip HTML tags for readability (basic)
        import re
        text = re.sub(r'<style[^>]*>.*?</style>', '', html_text, flags=re.DOTALL | re.IGNORECASE)
        text = re.sub(r'<script[^>]*>.*?</script>', '', text, flags=re.DOTALL | re.IGNORECASE)
        text = re.sub(r'<[^>]+>', ' ', text)
        text = re.sub(r'\s+', ' ', text).strip()
        # Also decode HTML entities
        import html
        text = html.unescape(text)
        payload['decodedBody'] = text
        payload['bodyType'] = 'text/html (stripped)'

    # Remove raw base64 body data since we've decoded it
    if 'decodedBody' in payload:
        # Remove body.data from main body
        if 'body' in payload and 'data' in payload.get('body', {}):
            payload['body'] = {k: v for k, v in payload['body'].items() if k != 'data'}
        # Remove body.data from parts recursively
        def strip_body_data(p):
            if isinstance(p, dict):
                if 'body' in p and isinstance(p['body'], dict) and 'data' in p['body']:
                    p['body'] = {k: v for k, v in p['body'].items() if k != 'data'}
                for part in p.get('parts', []):
                    strip_body_data(part)
        strip_body_data(payload)

    return payload


def is_gmail_message(data: dict) -> bool:
    """Check if data looks like a Gmail message response"""
    return (
        isinstance(data, dict) and
        'payload' in data and
        'id' in data and
        isinstance(data.get('payload'), dict) and
        ('body' in data['payload'] or 'parts' in data['payload'])
    )
