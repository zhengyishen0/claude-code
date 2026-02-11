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
import importlib.util
from pathlib import Path

# Load modules from specific paths (avoids namespace package conflicts)
def load_module_from_path(name: str, path: Path):
    """Load a Python module from a specific file path."""
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module

# Get skills directory
SKILLS_DIR = Path(__file__).parent.parent

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


# Register services using direct path loading
google_module = load_module_from_path('google_service', SKILLS_DIR / 'google' / '__init__.py')
cli.add_command(google_module.google_cli, name='google')

feishu_module = load_module_from_path('feishu_service', SKILLS_DIR / 'feishu' / '__init__.py')
cli.add_command(feishu_module.feishu_cli, name='feishu')

# Future services (uncomment when implemented)
# aws_module = load_module_from_path('aws_service', SKILLS_DIR / 'aws' / '__init__.py')
# cli.add_command(aws_module.aws_cli, name='aws')


if __name__ == '__main__':
    cli()
