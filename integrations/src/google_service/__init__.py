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
    """Authorize your Google account (user login)

    \b
    This opens a browser for you to log in and grant access.
    Requires admin setup first (api google admin setup).

    \b
    Examples:
        api google auth                         # All scopes
        api google auth --scopes gmail,calendar # Specific scopes
    """
    from .auth import AuthError, CLIENT_SECRET_PATH

    # Check if admin setup is done
    if not CLIENT_SECRET_PATH.exists():
        click.echo("❌ Admin setup required first.")
        click.echo("   Run: api google admin setup")
        sys.exit(1)

    scope_list = scopes.split(',') if scopes else None
    try:
        authorize(scope_list, interactive=False)  # No interactive setup, just OAuth
        click.echo("\n✅ Authorization complete. You can now use Google APIs.")
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


# Mapping of service names to API identifiers for gcloud
API_IDENTIFIERS = {
    'gmail': 'gmail.googleapis.com',
    'calendar': 'calendar-json.googleapis.com',
    'drive': 'drive.googleapis.com',
    'sheets': 'sheets.googleapis.com',
    'docs': 'docs.googleapis.com',
    'tasks': 'tasks.googleapis.com',
    'contacts': 'people.googleapis.com',  # Contacts uses People API
}


@google_cli.command('admin')
def admin():
    """One-time project setup (run this first)

    \b
    This will:
    1. Guide you to create OAuth credentials in Google Cloud Console
    2. Auto-detect client_secret.json from ~/Downloads
    3. Enable all required APIs via gcloud (if installed)

    \b
    After setup, users can run: api google auth
    """
    import subprocess
    import shutil
    from .auth import setup_client_secret_interactive, CLIENT_SECRET_PATH

    click.echo("\n" + "=" * 60)
    click.echo("  Google API - Admin Setup")
    click.echo("=" * 60)

    # Step 1: Check/setup OAuth credentials
    if CLIENT_SECRET_PATH.exists():
        click.echo("\n✅ Step 1: OAuth credentials already configured")
        click.echo(f"   {CLIENT_SECRET_PATH}")
    else:
        click.echo("\n📋 Step 1: OAuth Credentials Setup")
        if not setup_client_secret_interactive():
            sys.exit(1)
        click.echo("   ✅ Credentials saved")

    # Step 2: Extract and show project ID
    try:
        data = json.loads(CLIENT_SECRET_PATH.read_text())
        installed = data.get('installed', data.get('web', {}))
        project_id = installed.get('project_id')
        click.echo(f"\n✅ Step 2: Project ID: {project_id}")
    except Exception as e:
        click.echo(f"\n❌ Step 2: Could not read project ID: {e}")
        sys.exit(1)

    # Step 3: Enable APIs via gcloud
    click.echo(f"\n📋 Step 3: Enable APIs")

    if not shutil.which('gcloud'):
        click.echo("   ⚠️  gcloud CLI not found - skipping API enabling")
        click.echo("   Install: brew install google-cloud-sdk")
        click.echo("   Then run: gcloud auth login && api google admin")
        click.echo("\n   Or enable APIs manually at:")
        click.echo(f"   https://console.cloud.google.com/apis/library?project={project_id}")
    else:
        click.echo(f"   Enabling {len(API_IDENTIFIERS)} APIs...")
        apis = list(API_IDENTIFIERS.values())
        cmd = ['gcloud', 'services', 'enable'] + apis + [f'--project={project_id}']

        try:
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode == 0:
                click.echo("   ✅ All APIs enabled:")
                for name in API_IDENTIFIERS.keys():
                    click.echo(f"      • {name}")
            else:
                if "PERMISSION_DENIED" in result.stderr:
                    click.echo("   ⚠️  Permission denied - run 'gcloud auth login' first")
                else:
                    click.echo(f"   ⚠️  Could not enable APIs: {result.stderr.strip()}")
                click.echo("\n   Enable APIs manually at:")
                click.echo(f"   https://console.cloud.google.com/apis/library?project={project_id}")
        except Exception as e:
            click.echo(f"   ⚠️  gcloud error: {e}")

    # Done
    click.echo("\n" + "=" * 60)
    click.echo("  ✅ Admin setup complete!")
    click.echo("  Users can now run: api google auth")
    click.echo("=" * 60 + "\n")


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
