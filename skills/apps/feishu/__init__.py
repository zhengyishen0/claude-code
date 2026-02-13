"""Feishu/Lark API service for the service tool

CLI Structure:
    service feishu admin [setup|status|logout]
    service feishu bot [start|stop|status]
    service feishu bitable <action> [args]
    service feishu im <action> [args]
    service feishu calendar <action> [args]
    service feishu vc <action> [args]
"""

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
from .bot import cli_start as bot_start, cli_start_cc as bot_start_cc, cli_status as bot_status, BotError
from .commands import bitable, im, calendar, vc


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


# Bot subcommand group
@feishu_cli.group('bot')
def bot():
    """Feishu Bot listener (WebSocket long connection)

    \b
    Listen for messages sent to your Feishu bot in real-time.

    \b
    Prerequisites:
        1. Run 'service feishu admin' to configure credentials
        2. Enable 'im:message' event in Feishu Open Platform console
        3. Configure event subscription (WebSocket mode)

    \b
    Commands:
        service feishu bot status   Check bot configuration
        service feishu bot start    Start listening for messages
    """
    pass


@bot.command('status')
def bot_status_cmd():
    """Check if bot is configured and ready

    \b
    This checks:
    - Credentials are configured
    - App ID and secret are present

    \b
    Note: To fully verify, you need to enable 'im:message' event
    in the Feishu Open Platform console under Event Subscriptions.
    """
    status_info = bot_status()
    click.echo(json.dumps(status_info, indent=2))


@bot.command('start')
@click.option('--debug', is_flag=True, help='Enable debug logging')
def bot_start_cmd(debug):
    """Start the bot listener (WebSocket long connection)

    
    This starts a WebSocket connection to Feishu and listens for
    im.message.receive_v1 events (messages sent to your bot).

    
    The connection will:
    - Auto-reconnect on disconnection
    - Print received messages to stdout
    - Keep running until Ctrl+C

    
    Prerequisites:
        1. Configure credentials: service feishu admin
        2. In Feishu Open Platform console:
           - Go to Event Subscriptions
           - Enable WebSocket mode
           - Add 'im.message.receive_v1' event
           - Grant 'im:message' permission

    
    Example:
        service feishu bot start
        service feishu bot start --debug
    """
    bot_start_cc(verbose=debug)


# =============================================================================
# High-level command groups: bitable, im, calendar, vc
# =============================================================================

def _create_action_command(module, group_name: str):
    """Create a Click command group for a module with actions."""

    @click.command(name=group_name)
    @click.argument('action', required=False)
    @click.argument('params', nargs=-1)
    @click.pass_context
    def action_cmd(ctx, action, params):
        # Get the module from the context
        mod = ctx.obj

        # If no action, show help
        if not action:
            click.echo(f"Available {group_name} actions:\n")
            for name, desc in mod.get_actions().items():
                click.echo(f"  {name:<20} {desc}")
            click.echo()
            click.echo(f"Usage: service feishu {group_name} <action> [key=value ...]")
            click.echo()
            click.echo(f"Example: service feishu {group_name} {list(mod.get_actions().keys())[0]} ...")
            return

        # Check if action exists
        actions = mod.get_actions()
        if action not in actions:
            click.echo(f"Unknown action: {action}", err=True)
            click.echo(f"\nAvailable actions: {', '.join(actions.keys())}")
            sys.exit(1)

        # Parse params: key=value pairs
        param_dict = {}
        for p in params:
            if '=' in p:
                k, v = p.split('=', 1)
                # Try to parse as JSON for complex values
                try:
                    v = json.loads(v)
                except (json.JSONDecodeError, ValueError):
                    pass
                param_dict[k] = v
            else:
                click.echo(f"Invalid parameter format: {p}", err=True)
                click.echo("Parameters must be in key=value format")
                sys.exit(1)

        # Run the action
        try:
            result = mod.run_action(action, param_dict)
            click.echo(json.dumps(result, indent=2, ensure_ascii=False))
        except ValueError as e:
            click.echo(f"Error: {e}", err=True)
            sys.exit(1)
        except AuthError as e:
            click.echo(f"Auth Error: {e}", err=True)
            sys.exit(1)
        except Exception as e:
            click.echo(f"Error: {e}", err=True)
            sys.exit(1)

    return action_cmd


@feishu_cli.command('bitable')
@click.argument('action', required=False)
@click.argument('params', nargs=-1)
def bitable_cmd(action, params):
    """Bitable (Base) - database tables and records

    \b
    Bitable is Feishu's database product, similar to Airtable.
    Manage tables, fields, and records programmatically.

    \b
    Actions:
        list_tables     List all tables in a base
        list_fields     List all fields (columns) in a table
        list_records    List records with optional filtering
        get_record      Get a single record by ID
        create_record   Create a new record
        update_record   Update an existing record
        delete_record   Delete a record

    \b
    Examples:
        service feishu bitable list_tables app_token=bascnXXX
        service feishu bitable list_fields app_token=bascnXXX table_id=tblXXX
        service feishu bitable list_records app_token=bascnXXX table_id=tblXXX
        service feishu bitable get_record app_token=bascnXXX table_id=tblXXX record_id=recXXX
    """
    _run_action_command(bitable, 'bitable', action, params)


@feishu_cli.command('im')
@click.argument('action', required=False)
@click.argument('params', nargs=-1)
def im_cmd(action, params):
    """IM - instant messaging

    \b
    Send messages, manage chats, and interact with users.

    \b
    Actions:
        send        Send a text message to a chat
        send_card   Send an interactive card message
        reply       Reply to a specific message
        list_chats  List chats the bot is in
        bot_info    Get bot information

    \b
    Examples:
        service feishu im send chat_id=oc_XXX text="Hello!"
        service feishu im reply message_id=om_XXX text="Thanks!"
        service feishu im list_chats
        service feishu im bot_info
    """
    _run_action_command(im, 'im', action, params)


@feishu_cli.command('calendar')
@click.argument('action', required=False)
@click.argument('params', nargs=-1)
def calendar_cmd(action, params):
    """Calendar - events and scheduling

    \b
    Manage calendars and events in Feishu Calendar.

    \b
    Actions:
        list_calendars  List all calendars
        list_events     List events in a calendar
        get_event       Get a single event by ID
        create_event    Create a new event
        update_event    Update an existing event
        delete_event    Delete an event

    \b
    Examples:
        service feishu calendar list_calendars
        service feishu calendar list_events calendar_id=primary
        service feishu calendar get_event calendar_id=primary event_id=xxx
    """
    _run_action_command(calendar, 'calendar', action, params)


@feishu_cli.command('vc')
@click.argument('action', required=False)
@click.argument('params', nargs=-1)
def vc_cmd(action, params):
    """VC - video conference statistics

    \b
    Get video conference statistics and meeting information.

    \b
    Actions:
        top_users       Get top users by meeting time
        meeting_stats   Get aggregate meeting statistics

    \b
    Examples:
        service feishu vc top_users
        service feishu vc top_users days=30 limit=10
        service feishu vc meeting_stats days=7
    """
    _run_action_command(vc, 'vc', action, params)


def _run_action_command(module, group_name: str, action: str, params: tuple):
    """Run an action from a command module."""
    # If no action, show help
    if not action:
        click.echo(f"Available {group_name} actions:\n")
        for name, desc in module.get_actions().items():
            click.echo(f"  {name:<20} {desc}")
        click.echo()
        click.echo(f"Usage: service feishu {group_name} <action> [key=value ...]")
        click.echo()
        actions_list = list(module.get_actions().keys())
        if actions_list:
            click.echo(f"Example: service feishu {group_name} {actions_list[0]} ...")
        return

    # Check if action exists
    actions = module.get_actions()
    if action not in actions:
        click.echo(f"Unknown action: {action}", err=True)
        click.echo(f"\nAvailable actions: {', '.join(actions.keys())}")
        sys.exit(1)

    # Parse params: key=value pairs
    param_dict = {}
    for p in params:
        if '=' in p:
            k, v = p.split('=', 1)
            # Try to parse as JSON for complex values
            try:
                v = json.loads(v)
            except (json.JSONDecodeError, ValueError):
                pass
            param_dict[k] = v
        else:
            click.echo(f"Invalid parameter format: {p}", err=True)
            click.echo("Parameters must be in key=value format")
            sys.exit(1)

    # Run the action
    try:
        result = module.run_action(action, param_dict)
        click.echo(json.dumps(result, indent=2, ensure_ascii=False))
    except ValueError as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)
    except AuthError as e:
        click.echo(f"Auth Error: {e}", err=True)
        sys.exit(1)
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)
