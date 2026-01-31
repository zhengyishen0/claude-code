"""Feishu/Lark API service for the service tool"""

import click
import json
import sys

from .auth import (
    setup_interactive,
    get_status,
    revoke_credentials,
    verify_credentials,
    AuthError,
    CREDENTIALS_PATH,
)
from .api import call_api, list_domains, SERVICE_DOMAINS


@click.group(invoke_without_command=True)
@click.pass_context
def feishu_cli(ctx):
    """Feishu/Lark APIs (Messaging, Calendar, Drive, Docs, etc.)

    \b
    First, set up your Feishu app:
        service feishu admin

    Then call any Feishu API:
        service feishu <domain> <api-path> [params...]

    \b
    Examples:
        service feishu domains                    # List available domains
        service feishu im messages ...         # Send message
        service feishu calendar calendars ...  # Calendar operations
        service feishu contact users ...       # Contact operations
    """
    if ctx.invoked_subcommand is None:
        click.echo(ctx.get_help())


@feishu_cli.command('admin')
def admin():
    """One-time setup - configure Feishu app credentials

    \b
    This will guide you through:
    1. Creating an app on Feishu/Lark Open Platform
    2. Getting your App ID and App Secret
    3. Saving credentials locally

    \b
    After setup, you can call Feishu APIs directly.
    """
    print("\n" + "=" * 60)
    print("  Feishu/Lark API - Admin Setup")
    print("=" * 60)

    if CREDENTIALS_PATH.exists():
        print("\n  Credentials already configured.")
        print(f"  Path: {CREDENTIALS_PATH}")
        print()
        try:
            choice = input("  Reconfigure? [y/N]: ").strip().lower()
            if choice != 'y':
                print("  Setup cancelled.")
                return
        except KeyboardInterrupt:
            print("\n  Setup cancelled.")
            return

    if setup_interactive():
        print()
        print("=" * 60)
        print("  Setup complete!")
        print()
        print("  Next steps:")
        print("    1. Configure API permissions in Feishu Open Platform")
        print("       (Permissions & Scopes section)")
        print()
        print("    2. Test with: service feishu status")
        print()
        print("    3. Try an API: service feishu domains")
        print("=" * 60)
    else:
        sys.exit(1)


@feishu_cli.command('status')
def status():
    """Check Feishu configuration status"""
    info = get_status()
    click.echo(json.dumps(info, indent=2))


@feishu_cli.command('verify')
def verify():
    """Verify Feishu credentials are working"""
    try:
        result = verify_credentials()
        click.echo(json.dumps(result, indent=2))
    except AuthError as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@feishu_cli.command('revoke')
def revoke():
    """Remove stored Feishu credentials"""
    if revoke_credentials():
        click.echo("Feishu credentials removed.")
    else:
        click.echo("No credentials found.")


@feishu_cli.command('domains')
def domains():
    """List available Feishu API domains"""
    click.echo("Available Feishu API domains:\n")
    for domain in list_domains():
        click.echo(f"  {domain['name']:<12} {domain['version']:<4}  {domain['description']}")
    click.echo()
    click.echo("Usage: service feishu <domain> <api-path> [params...]")
    click.echo()
    click.echo("Example:")
    click.echo("  service feishu im messages receive_id_type=chat_id --body '{...}'")


# Dynamic command for each domain
@feishu_cli.command('call')
@click.argument('api_path')
@click.argument('params', nargs=-1)
@click.option('--body', '-b', default=None, help='JSON request body')
@click.option('--raw', is_flag=True, help='Output raw response')
def call(api_path, params, body, raw):
    """Call any Feishu API by path

    \b
    API_PATH: Full API path like 'im/v1/messages' or 'contact/v3/users/:user_id'

    \b
    Examples:
        service feishu call im/v1/messages receive_id_type=chat_id --body '{"receive_id":"oc_xxx",...}'
        service feishu call contact/v3/users/:user_id user_id=xxx user_id_type=open_id
        service feishu call calendar/v4/calendars/primary/events page_size=10
    """
    # Parse params
    param_dict = {}
    for p in params:
        if '=' in p:
            k, v = p.split('=', 1)
            try:
                v = json.loads(v)
            except (json.JSONDecodeError, ValueError):
                pass
            param_dict[k] = v

    # Parse body
    body_dict = None
    if body:
        try:
            body_dict = json.loads(body)
        except json.JSONDecodeError as e:
            click.echo(f"Invalid JSON body: {e}", err=True)
            sys.exit(1)

    try:
        result = call_api_by_path(api_path, param_dict, body_dict)
        click.echo(json.dumps(result, indent=2, ensure_ascii=False))
    except AuthError as e:
        click.echo(f"Auth Error: {e}", err=True)
        sys.exit(1)
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


def call_api_by_path(api_path: str, params: dict, body: dict) -> dict:
    """
    Call Feishu API by full path.

    Args:
        api_path: Full path like 'im/v1/messages' or 'contact/v3/users/:user_id'
        params: Query parameters
        body: Request body
    """
    # The api_path should be the path after /open-apis/
    # e.g., 'im/v1/messages' or 'contact/v3/users/:user_id'

    # Replace path parameters like :user_id with actual values from params
    import re
    path_params = re.findall(r':(\w+)', api_path)
    for param in path_params:
        if param in params:
            api_path = api_path.replace(f':{param}', str(params[param]))
            del params[param]

    return call_api('', api_path, params, body)


# Register domain-specific commands
def create_domain_command(domain_name: str, domain_info: dict):
    """Create a click command for a Feishu domain"""

    @click.command(name=domain_name)
    @click.argument('api_path')
    @click.argument('params', nargs=-1)
    @click.option('--body', '-b', default=None, help='JSON request body')
    @click.pass_context
    def domain_cmd(ctx, api_path, params, body):
        # Get domain from command name
        dom = ctx.info_name
        version = SERVICE_DOMAINS[dom]['version']

        # Parse params
        param_dict = {}
        for p in params:
            if '=' in p:
                k, v = p.split('=', 1)
                try:
                    v = json.loads(v)
                except (json.JSONDecodeError, ValueError):
                    pass
                param_dict[k] = v

        # Parse body
        body_dict = None
        if body:
            try:
                body_dict = json.loads(body)
            except json.JSONDecodeError as e:
                click.echo(f"Invalid JSON body: {e}", err=True)
                sys.exit(1)

        # Build full path
        full_path = f"{dom}/{version}/{api_path}"

        try:
            result = call_api_by_path(full_path, param_dict, body_dict)
            click.echo(json.dumps(result, indent=2, ensure_ascii=False))
        except AuthError as e:
            click.echo(f"Auth Error: {e}", err=True)
            sys.exit(1)
        except Exception as e:
            click.echo(f"Error: {e}", err=True)
            sys.exit(1)

    # Set docstring
    domain_cmd.__doc__ = f"""{domain_info['description']}

    \b
    API_PATH: Resource path, e.g., 'calendars', 'messages', 'users'

    \b
    Example:
        service feishu {domain_name} <resource> [params...]
    """

    return domain_cmd


# Register all domain commands
for domain_name, domain_info in SERVICE_DOMAINS.items():
    cmd = create_domain_command(domain_name, domain_info)
    feishu_cli.add_command(cmd)
