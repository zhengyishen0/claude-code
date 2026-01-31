"""Gmail reply plugin - Reply to emails with proper threading"""

import base64
import re
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.utils import formatdate, make_msgid
from typing import Optional

from ...api import call_api


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
            text = re.sub(r'<[^>]+>', '', html)
            text = re.sub(r'\s+', ' ', text)
            return text.strip()

    return '(no text content)'


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


def run(args: dict) -> dict:
    """Plugin entry point"""
    # Parse reply_all as boolean if it's a string
    reply_all = args.get('reply_all', False)
    if isinstance(reply_all, str):
        reply_all = reply_all.lower() in ('true', '1', 'yes')

    return reply_email(
        message_id=args['message_id'],
        reply_body=args['body'],
        reply_all=reply_all
    )
