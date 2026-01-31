"""Gmail send plugin - Compose and send new emails"""

import base64
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.utils import formatdate, make_msgid
from typing import Optional

from ...api import call_api


def send_email(
    to_address: str,
    subject: str,
    body: str,
    cc_address: Optional[str] = None,
    bcc_address: Optional[str] = None,
    html: bool = False
) -> dict:
    """
    Compose and send a new email.

    Args:
        to_address: Recipient email address
        subject: Email subject
        body: Email body (plain text or HTML)
        cc_address: Optional CC address
        bcc_address: Optional BCC address
        html: If True, treat body as HTML

    Returns:
        API response with sent message details
    """
    # Get sender's email
    profile = call_api('gmail', 'users.getProfile', {'userId': 'me'})
    sender_email = profile['emailAddress']

    # Create the email
    if html:
        # Create multipart for HTML with plain text fallback
        msg = MIMEMultipart('alternative')

        # Plain text version (basic)
        import re
        plain_body = re.sub(r'<[^>]+>', '', body)
        plain_body = re.sub(r'\s+', ' ', plain_body).strip()
        text_part = MIMEText(plain_body, 'plain', 'utf-8')
        msg.attach(text_part)

        # HTML version
        html_part = MIMEText(body, 'html', 'utf-8')
        msg.attach(html_part)
    else:
        # Plain text only
        msg = MIMEText(body, 'plain', 'utf-8')

    # Set headers
    msg['From'] = sender_email
    msg['To'] = to_address
    if cc_address:
        msg['Cc'] = cc_address
    if bcc_address:
        msg['Bcc'] = bcc_address
    msg['Subject'] = subject
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
        'bcc': bcc_address,
        'subject': subject
    }


def run(args):
    """Plugin entry point - accepts single op or list of ops"""
    from concurrent.futures import ThreadPoolExecutor

    # Handle both single dict and list of dicts
    if isinstance(args, dict):
        operations = [args]
    else:
        operations = args

    def process_one(op):
        html = op.get('html', False)
        if isinstance(html, str):
            html = html.lower() in ('true', '1', 'yes')
        return send_email(
            to_address=op['to'],
            subject=op['subject'],
            body=op['body'],
            cc_address=op.get('cc'),
            bcc_address=op.get('bcc'),
            html=html
        )

    if len(operations) == 1:
        return process_one(operations[0])

    with ThreadPoolExecutor(max_workers=10) as executor:
        results = list(executor.map(process_one, operations))
    return results
