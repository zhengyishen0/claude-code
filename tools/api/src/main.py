#!/usr/bin/env python3
"""
api - Universal API tool for AI agents

Usage:
    api                     Show help
    api --list              List available services
    api google ...          Google APIs (Gmail, Calendar, Drive, etc.)
    api aws ...             AWS APIs (coming soon)
    api stripe ...          Stripe APIs (coming soon)
"""

import click
import sys

@click.group(invoke_without_command=True)
@click.option('--list', 'list_services', is_flag=True, help='List available services')
@click.pass_context
def cli(ctx, list_services):
    """Universal API tool for AI agents

    \b
    Examples:
        api --list
        api google auth
        api google gmail users.messages.list userId=me
        api google calendar events.list calendarId=primary
    """
    if list_services:
        click.echo("Available services:")
        click.echo("  google    Google APIs (Gmail, Calendar, Drive, Sheets, etc.)")
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

# Future services (uncomment when implemented)
# from aws import aws_cli
# cli.add_command(aws_cli, name='aws')


if __name__ == '__main__':
    cli()
