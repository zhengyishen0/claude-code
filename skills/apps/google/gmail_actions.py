"""Gmail email actions - Forward and Reply functionality"""

import base64
import json
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders
from email.utils import formatdate, make_msgid
from typing import Optional

from .api import call_api, get_service


def get_message_raw(message_id: str) -> dict:
    """Get a message in raw format for forwarding as .eml"""
    return call_api(
        'gmail',
        'users.messages.get',
        {'userId': 'me', 'id': message_id, 'format': 'raw'}
    )


def get_message_full(message_id: str) -> dict:
    """Get a message with full metadata for replying"""
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


def forward_email(
    message_id: str,
    to_address: str,
    cc_address: Optional[str] = None,
    forward_note: Optional[str] = None
) -> dict:
    """
    Forward an email by attaching the original as .eml

    Args:
        message_id: The Gmail message ID to forward
        to_address: Recipient email address
        cc_address: Optional CC address
        forward_note: Optional note to include in the forward

    Returns:
        API response with sent message details
    """
    # Get the original message in raw format
    original = get_message_raw(message_id)
    raw_email = base64.urlsafe_b64decode(original['raw'])

    # Get full message for headers (subject, from, etc.)
    full_msg = get_message_full(message_id)
    headers = full_msg.get('payload', {}).get('headers', [])

    original_subject = get_header(headers, 'Subject') or '(no subject)'
    original_from = get_header(headers, 'From') or 'Unknown'
    original_date = get_header(headers, 'Date') or 'Unknown'
    original_to = get_header(headers, 'To') or ''

    # Get sender's email for From header
    profile = call_api('gmail', 'users.getProfile', {'userId': 'me'})
    sender_email = profile['emailAddress']

    # Create the forwarding email
    msg = MIMEMultipart('mixed')
    msg['From'] = sender_email
    msg['To'] = to_address
    if cc_address:
        msg['Cc'] = cc_address
    msg['Subject'] = f"Fwd: {original_subject}"
    msg['Date'] = formatdate(localtime=True)
    msg['Message-ID'] = make_msgid()

    # Create the text body with forward header
    forward_header = f"""
---------- Forwarded message ---------
From: {original_from}
Date: {original_date}
Subject: {original_subject}
To: {original_to}
"""

    body_text = forward_note + "\n" if forward_note else ""
    body_text += forward_header

    text_part = MIMEText(body_text, 'plain', 'utf-8')
    msg.attach(text_part)

    # Attach the original email as .eml
    eml_attachment = MIMEBase('message', 'rfc822')
    eml_attachment.set_payload(raw_email)
    encoders.encode_base64(eml_attachment)

    # Create a clean filename from subject
    safe_subject = ''.join(c for c in original_subject[:50] if c.isalnum() or c in ' -_').strip()
    if not safe_subject:
        safe_subject = 'forwarded-email'

    eml_attachment.add_header(
        'Content-Disposition',
        'attachment',
        filename=f'{safe_subject}.eml'
    )
    msg.attach(eml_attachment)

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


def reply_email(
    message_id: str,
    reply_body: str,
    reply_all: bool = False
) -> dict:
    """
    Reply to an email with proper threading headers

    Args:
        message_id: The Gmail message ID to reply to
        reply_body: The reply message body
        reply_all: If True, reply to all recipients

    Returns:
        API response with sent message details
    """
    # Get the original message
    original = get_message_full(message_id)
    headers = original.get('payload', {}).get('headers', [])
    thread_id = original.get('threadId')

    # Extract headers we need
    original_subject = get_header(headers, 'Subject') or '(no subject)'
    original_from = get_header(headers, 'From') or ''
    original_to = get_header(headers, 'To') or ''
    original_cc = get_header(headers, 'Cc') or ''
    original_message_id = get_header(headers, 'Message-ID') or ''
    original_references = get_header(headers, 'References') or ''
    original_date = get_header(headers, 'Date') or ''

    # Get sender's email
    profile = call_api('gmail', 'users.getProfile', {'userId': 'me'})
    sender_email = profile['emailAddress']

    # Determine recipients
    # Reply goes to the From address of the original
    to_address = original_from
    cc_addresses = None

    if reply_all:
        # For reply-all, include original To and Cc, excluding ourselves
        all_recipients = []

        # Parse and collect all addresses from To
        if original_to:
            all_recipients.extend([addr.strip() for addr in original_to.split(',')])

        # Add original Cc
        if original_cc:
            all_recipients.extend([addr.strip() for addr in original_cc.split(',')])

        # Filter out our own email (case-insensitive)
        cc_list = [
            addr for addr in all_recipients
            if sender_email.lower() not in addr.lower()
        ]

        # Also exclude the From address since it's already in To
        if original_from:
            cc_list = [
                addr for addr in cc_list
                if original_from.lower() not in addr.lower()
            ]

        if cc_list:
            cc_addresses = ', '.join(cc_list)

    # Build subject with Re: prefix
    if original_subject.lower().startswith('re:'):
        subject = original_subject
    else:
        subject = f"Re: {original_subject}"

    # Build References header (for threading)
    if original_references:
        references = f"{original_references} {original_message_id}"
    else:
        references = original_message_id

    # Create the reply email
    msg = MIMEMultipart('alternative')
    msg['From'] = sender_email
    msg['To'] = to_address
    if cc_addresses:
        msg['Cc'] = cc_addresses
    msg['Subject'] = subject
    msg['Date'] = formatdate(localtime=True)
    msg['Message-ID'] = make_msgid()

    # Threading headers
    if original_message_id:
        msg['In-Reply-To'] = original_message_id
    if references:
        msg['References'] = references

    # Build the reply body with quoted original
    # Extract plain text from original message
    original_text = extract_text_from_payload(original.get('payload', {}))

    # Quote the original message
    quoted_lines = ['> ' + line for line in original_text.split('\n')]
    quoted_original = '\n'.join(quoted_lines)

    full_body = f"""{reply_body}

On {original_date}, {original_from} wrote:
{quoted_original}
"""

    text_part = MIMEText(full_body, 'plain', 'utf-8')
    msg.attach(text_part)

    # Also create an HTML version for better formatting
    html_body = f"""<div dir="ltr">
{reply_body.replace(chr(10), '<br>')}
<br><br>
<div class="gmail_quote">
<div dir="ltr" class="gmail_attr">On {original_date}, {original_from} wrote:<br></div>
<blockquote class="gmail_quote" style="margin:0px 0px 0px 0.8ex;border-left:1px solid rgb(204,204,204);padding-left:1ex">
{original_text.replace(chr(10), '<br>')}
</blockquote>
</div>
</div>"""

    html_part = MIMEText(html_body, 'html', 'utf-8')
    msg.attach(html_part)

    # Encode and send (include threadId for proper threading)
    raw_message = base64.urlsafe_b64encode(msg.as_bytes()).decode('utf-8')

    result = call_api(
        'gmail',
        'users.messages.send',
        {'userId': 'me'},
        body={'raw': raw_message, 'threadId': thread_id}
    )

    return {
        'status': 'sent',
        'messageId': result.get('id'),
        'threadId': result.get('threadId'),
        'to': to_address,
        'cc': cc_addresses,
        'subject': subject,
        'replyAll': reply_all
    }


def extract_text_from_payload(payload: dict) -> str:
    """
    Extract plain text content from a Gmail message payload

    Handles both simple messages and multipart messages
    """
    mime_type = payload.get('mimeType', '')

    # Simple text message
    if mime_type == 'text/plain':
        body = payload.get('body', {})
        data = body.get('data', '')
        if data:
            return base64.urlsafe_b64decode(data).decode('utf-8', errors='replace')
        return ''

    # Multipart message - look for text/plain part
    if mime_type.startswith('multipart/'):
        parts = payload.get('parts', [])
        for part in parts:
            part_type = part.get('mimeType', '')

            # Found plain text
            if part_type == 'text/plain':
                body = part.get('body', {})
                data = body.get('data', '')
                if data:
                    return base64.urlsafe_b64decode(data).decode('utf-8', errors='replace')

            # Nested multipart - recurse
            if part_type.startswith('multipart/'):
                text = extract_text_from_payload(part)
                if text:
                    return text

    # Fallback: try to get HTML and strip tags (basic)
    if mime_type == 'text/html':
        body = payload.get('body', {})
        data = body.get('data', '')
        if data:
            html = base64.urlsafe_b64decode(data).decode('utf-8', errors='replace')
            # Very basic tag stripping
            import re
            text = re.sub(r'<[^>]+>', '', html)
            text = re.sub(r'\s+', ' ', text)
            return text.strip()

    return '(no text content)'
