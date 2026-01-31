"""Gmail forward plugin - Forward emails with .eml attachment"""

import base64
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders
from email.utils import formatdate, make_msgid
from typing import Optional

from ...api import call_api


def get_message_raw(message_id: str) -> dict:
    """Get a message in raw format for forwarding as .eml"""
    return call_api(
        'gmail',
        'users.messages.get',
        {'userId': 'me', 'id': message_id, 'format': 'raw'}
    )


def get_message_full(message_id: str) -> dict:
    """Get a message with full metadata"""
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


def run(args: dict) -> dict:
    """Plugin entry point"""
    return forward_email(
        message_id=args['message_id'],
        to_address=args['to'],
        cc_address=args.get('cc'),
        forward_note=args.get('note')
    )
