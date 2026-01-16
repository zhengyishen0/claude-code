"""Google API service for the api tool"""

import click
import json
from .auth import authorize, get_status, revoke_auth
from .api import call_api, call_api_media
from .discovery import list_services, list_methods, get_method_help, SERVICE_VERSIONS


@click.group(invoke_without_command=True)
@click.pass_context
def google_cli(ctx):
    """Google APIs (Gmail, Calendar, Drive, Sheets, etc.)

    \b
    First, authorize your Google account:
        api google auth

    Then call any Google API:
        api google <service> <method> [params...]

    \b
    Examples:
        api google gmail users.messages.list userId=me
        api google gmail users.messages.list userId=me q="is:unread"
        api google calendar events.list calendarId=primary
        api google drive files.list
        api google sheets spreadsheets.get spreadsheetId=xxx
    """
    if ctx.invoked_subcommand is None:
        click.echo(ctx.get_help())


@google_cli.command('auth')
@click.option('--scopes', '-s', default=None,
              help='Comma-separated scopes: gmail,calendar,drive,sheets,docs,contacts,tasks')
def auth(scopes):
    """Authorize Google account (interactive setup)

    \b
    This will:
    1. Check if OAuth credentials exist
    2. If not, guide you through setup (just paste JSON)
    3. Open browser for you to click "Allow"

    \b
    Examples:
        api google auth                         # All scopes
        api google auth --scopes gmail,calendar # Specific scopes
    """
    from .auth import AuthError

    scope_list = scopes.split(',') if scopes else None
    try:
        authorize(scope_list, interactive=True)
        click.echo("\n✅ Google authorization complete. You can now use all Google APIs.")
    except AuthError as e:
        click.echo(f"\n❌ {e}", err=True)
        sys.exit(1)
    except Exception as e:
        click.echo(f"\n❌ Unexpected error: {e}", err=True)
        sys.exit(1)


@google_cli.command('status')
def status():
    """Check Google authorization status"""
    info = get_status()
    click.echo(json.dumps(info, indent=2))


@google_cli.command('revoke')
def revoke():
    """Revoke Google authorization"""
    if revoke_auth():
        click.echo("✅ Google authorization revoked.")
    else:
        click.echo("❌ No authorization found.")


@google_cli.command('services')
def services():
    """List available Google services"""
    for name, version in sorted(SERVICE_VERSIONS.items()):
        click.echo(f"  {name:<12} (API {version})")


# The main API command - handles dynamic service/method calls
@google_cli.command('api', hidden=True)
@click.argument('args', nargs=-1)
def api_cmd(args):
    """Internal: redirect to service commands"""
    click.echo("Use: api google <service> <method> [params...]")


def register_service_commands():
    """Dynamically register commands for each Google service"""
    for service_name in SERVICE_VERSIONS.keys():
        create_service_command(service_name)


def create_service_command(service_name: str):
    """Create a click command for a Google service"""

    @click.command(name=service_name)
    @click.argument('method', required=False)
    @click.argument('params', nargs=-1)
    @click.option('--body', '-b', default=None, help='JSON request body')
    @click.option('--list-methods', 'list_mth', is_flag=True, help='List available methods')
    @click.option('--help-method', 'help_mth', is_flag=True, help='Show method details')
    @click.option('--output', '-o', default=None, help='Output file (for binary responses)')
    @click.option('--raw', is_flag=True, help='Output raw response without noise filtering')
    @click.pass_context
    def service_cmd(ctx, method, params, body, list_mth, help_mth, output, raw):
        # Get service name from command name
        svc_name = ctx.info_name

        # Import cleaner for response filtering
        from cleaner import clean_response

        # List methods
        if list_mth or method is None:
            click.echo(f"Methods for {svc_name}:")
            click.echo(f"(Use --help-method for details: api google {svc_name} <method> --help-method)\n")
            try:
                methods = list_methods(svc_name)
                for m in methods:
                    click.echo(f"  {m['name']}")
            except Exception as e:
                click.echo(f"❌ Error listing methods: {e}", err=True)
            return

        # Help for specific method
        if help_mth:
            try:
                info = get_method_help(svc_name, method)
                click.echo(json.dumps(info, indent=2))
            except Exception as e:
                click.echo(f"❌ Error getting method help: {e}", err=True)
            return

        # Parse params: "userId=me" "q=is:unread" → {"userId": "me", "q": "is:unread"}
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

        # Parse body
        body_dict = None
        if body:
            try:
                body_dict = json.loads(body)
            except json.JSONDecodeError as e:
                click.echo(f"❌ Invalid JSON body: {e}", err=True)
                return

        # Check if this is a media download method
        media_methods = ['files.export', 'files.get_media']
        is_media = any(method.endswith(m.split('.')[-1]) for m in media_methods)

        try:
            if is_media and output:
                result = call_api_media(svc_name, method, param_dict)
                with open(output, 'wb') as f:
                    f.write(result)
                click.echo(f"✅ Saved to {output}")
            else:
                result = call_api(svc_name, method, param_dict, body_dict)
                # Clean response by default, unless --raw is specified
                if not raw:
                    result = clean_response(result)
                click.echo(json.dumps(result, indent=2, ensure_ascii=False))
        except Exception as e:
            click.echo(f"❌ API Error: {e}", err=True)
            sys.exit(1)

    # Set the docstring dynamically
    service_cmd.__doc__ = f"""{service_name.title()} API

    \b
    Examples:
        api google {service_name} --list-methods
        api google {service_name} <method> --help-method
        api google {service_name} <method> [key=value ...]
    """

    google_cli.add_command(service_cmd)


# Register all service commands
import sys
register_service_commands()
