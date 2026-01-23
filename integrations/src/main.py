#!/usr/bin/env python3
"""
service - Universal service client for AI agents

Usage:
    service                     Show help
    service --list              List available services
    service google ...          Google APIs (Gmail, Calendar, Drive, etc.)
    service aws ...             AWS APIs (coming soon)
    service stripe ...          Stripe APIs (coming soon)
"""

import click
import sys

@click.group(invoke_without_command=True)
@click.option('--list', 'list_services', is_flag=True, help='List available services')
@click.pass_context
def cli(ctx, list_services):
    """Universal service client for AI agents

    \b
    Examples:
        service --list
        service google auth
        service google gmail users.messages.list userId=me
        service google calendar events.list calendarId=primary
    """
    if list_services:
        click.echo("Available services:")
        click.echo("  google    Google APIs (Gmail, Calendar, Drive, Sheets, etc.)")
        click.echo("  feishu    Feishu/Lark APIs (Messaging, Calendar, Drive, Docs, etc.)")
        click.echo("  aws       AWS APIs (coming soon)")
        click.echo("  stripe    Stripe APIs (coming soon)")
        click.echo("  slack     Slack APIs (coming soon)")
        click.echo("  github    GitHub APIs (coming soon)")
        return

    if ctx.invoked_subcommand is None:
        click.echo(ctx.get_help())


# Register services
from google_service import google_cli
cli.add_command(google_cli, name='google')

from feishu_service import feishu_cli
cli.add_command(feishu_cli, name='feishu')

# Future services (uncomment when implemented)
# from aws import aws_cli
# cli.add_command(aws_cli, name='aws')


if __name__ == '__main__':
    cli()
