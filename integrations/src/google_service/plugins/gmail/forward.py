"""Gmail forward plugin - Forward emails with inline content (like normal Gmail forward)"""

import base64
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.utils import formatdate, make_msgid
from typing import Optional, Tuple

from ...api import call_api


def get_message_full(message_id: str) -> dict:
    """Get a message with full metadata and body"""
    return call_api(
        'gmail',
        'users.messages.get',
        {'userId': 'me', 'id': message_id, 'format': 'full'}
    )


def get_header(headers: list, name: str) -> Optional[str]:
    """Extract a header value from headers list"""
    for header in headers:
        if header['name'].lower() == name.lower():
            return header['value']
    return None


def extract_body(payload: dict) -> Tuple[Optional[str], Optional[str]]:
    """
    Extract plain text and HTML body from message payload.
    Handles nested MIME parts (multipart/alternative, multipart/mixed, etc.)

    Returns:
        Tuple of (plain_text_body, html_body) - either may be None
    """
    plain_body = None
    html_body = None

    mime_type = payload.get('mimeType', '')

    # Direct body (non-multipart)
    if 'body' in payload and payload['body'].get('data'):
        body_data = base64.urlsafe_b64decode(payload['body']['data']).decode('utf-8')
        if mime_type == 'text/plain':
            plain_body = body_data
        elif mime_type == 'text/html':
            html_body = body_data
        return plain_body, html_body

    # Multipart - recurse into parts
    if 'parts' in payload:
        for part in payload['parts']:
            part_mime = part.get('mimeType', '')

            if part_mime == 'text/plain' and not plain_body:
                if part.get('body', {}).get('data'):
                    plain_body = base64.urlsafe_b64decode(part['body']['data']).decode('utf-8')
            elif part_mime == 'text/html' and not html_body:
                if part.get('body', {}).get('data'):
                    html_body = base64.urlsafe_b64decode(part['body']['data']).decode('utf-8')
            elif part_mime.startswith('multipart/'):
                # Recurse into nested multipart
                nested_plain, nested_html = extract_body(part)
                if nested_plain and not plain_body:
                    plain_body = nested_plain
                if nested_html and not html_body:
                    html_body = nested_html

    return plain_body, html_body


def forward_email(
    message_id: str,
    to_address: str,
    cc_address: Optional[str] = None,
    forward_note: Optional[str] = None
) -> dict:
    """
    Forward an email with content inline (like a normal Gmail forward).

    Args:
        message_id: The Gmail message ID to forward
        to_address: Recipient email address
        cc_address: Optional CC address
        forward_note: Optional note to include before the forwarded content

    Returns:
        API response with sent message details
    """
    # Get full message for headers and body
    full_msg = get_message_full(message_id)
    payload = full_msg.get('payload', {})
    headers = payload.get('headers', [])

    original_subject = get_header(headers, 'Subject') or '(no subject)'
    original_from = get_header(headers, 'From') or 'Unknown'
    original_date = get_header(headers, 'Date') or 'Unknown'
    original_to = get_header(headers, 'To') or ''

    # Extract body content
    plain_body, html_body = extract_body(payload)

    # Get sender's email for From header
    profile = call_api('gmail', 'users.getProfile', {'userId': 'me'})
    sender_email = profile['emailAddress']

    # Forward header text (for plain text version)
    forward_header_text = f"""---------- Forwarded message ---------
From: {original_from}
Date: {original_date}
Subject: {original_subject}
To: {original_to}

"""

    # Forward header HTML (for HTML version)
    forward_header_html = f"""<div style="margin: 20px 0; padding: 10px 0; border-top: 1px solid #ccc;">
<span style="color: #777;">---------- Forwarded message ---------</span><br>
<b>From:</b> {original_from}<br>
<b>Date:</b> {original_date}<br>
<b>Subject:</b> {original_subject}<br>
<b>To:</b> {original_to}
</div>
"""

    # Build the forwarded content
    note_text = (forward_note + "\n\n") if forward_note else ""
    note_html = (f"<div>{forward_note}</div><br>") if forward_note else ""

    # Determine if we need multipart/alternative (has both plain and HTML)
    has_html = html_body is not None

    if has_html:
        # Create multipart/alternative for HTML email
        msg = MIMEMultipart('alternative')

        # Plain text version
        plain_content = note_text + forward_header_text + (plain_body or html_body or '')
        text_part = MIMEText(plain_content, 'plain', 'utf-8')
        msg.attach(text_part)

        # HTML version
        html_content = f"""<html>
<body>
{note_html}
{forward_header_html}
<div>
{html_body}
</div>
</body>
</html>"""
        html_part = MIMEText(html_content, 'html', 'utf-8')
        msg.attach(html_part)
    else:
        # Plain text only
        msg = MIMEText(note_text + forward_header_text + (plain_body or ''), 'plain', 'utf-8')

    # Set headers
    msg['From'] = sender_email
    msg['To'] = to_address
    if cc_address:
        msg['Cc'] = cc_address
    msg['Subject'] = f"Fwd: {original_subject}"
    msg['Date'] = formatdate(localtime=True)
    msg['Message-ID'] = make_msgid()

    # Encode and send
    raw_message = base64.urlsafe_b64encode(msg.as_bytes()).decode('utf-8')

    result = call_api(
        'gmail',
        'users.messages.send',
        {'userId': 'me'},
        body={'raw': raw_message}
    )

    return {
        'status': 'sent',
        'messageId': result.get('id'),
        'threadId': result.get('threadId'),
        'to': to_address,
        'cc': cc_address,
        'subject': f"Fwd: {original_subject}"
    }


def run(args: dict) -> dict:
    """Plugin entry point"""
    return forward_email(
        message_id=args['message_id'],
        to_address=args['to'],
        cc_address=args.get('cc'),
        forward_note=args.get('note')
    )
