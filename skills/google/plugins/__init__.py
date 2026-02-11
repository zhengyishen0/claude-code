"""Plugin loader for Google service actions"""

import importlib
from pathlib import Path
from typing import Optional

import yaml


# Load plugin registry
_PLUGINS_PATH = Path(__file__).parent.parent.parent.parent / 'plugins.yaml'
_REGISTRY = None


def _load_registry() -> dict:
    """Load and cache the plugin registry"""
    global _REGISTRY
    if _REGISTRY is None:
        if _PLUGINS_PATH.exists():
            with open(_PLUGINS_PATH) as f:
                _REGISTRY = yaml.safe_load(f) or {}
        else:
            _REGISTRY = {}
    return _REGISTRY


def get_plugin(service: str, action: str) -> Optional[dict]:
    """
    Get plugin configuration for a service action.

    Args:
        service: Service name (e.g., 'gmail')
        action: Action name (e.g., 'forward', 'reply')

    Returns:
        Plugin config dict or None if not found
    """
    registry = _load_registry()
    service_plugins = registry.get(service, {})
    return service_plugins.get(action)


def list_plugins(service: str) -> list:
    """
    List all plugins for a service.

    Args:
        service: Service name (e.g., 'gmail')

    Returns:
        List of (action_name, description) tuples
    """
    registry = _load_registry()
    service_plugins = registry.get(service, {})
    return [
        (name, config.get('description', ''))
        for name, config in service_plugins.items()
    ]


def run_plugin(service: str, action: str, args):
    """
    Run a plugin action.

    Args:
        service: Service name (e.g., 'gmail')
        action: Action name (e.g., 'forward')
        args: Arguments - dict for single op, list of dicts for batch

    Returns:
        Result from the plugin's run() function

    Raises:
        ValueError: If plugin not found or missing required args
        ImportError: If plugin module can't be loaded
    """
    plugin = get_plugin(service, action)
    if not plugin:
        raise ValueError(f"Plugin not found: {service}.{action}")

    # Validate required args
    required = plugin.get('required_args', [])

    # Handle both single dict and list of dicts
    items_to_validate = args if isinstance(args, list) else [args]
    for i, item in enumerate(items_to_validate):
        missing = [arg for arg in required if arg not in item]
        if missing:
            prefix = f"Item {i}: " if isinstance(args, list) else ""
            raise ValueError(f"{prefix}Missing required arguments: {', '.join(missing)}")

    # Import and run the plugin module
    module_path = plugin['module']
    module = importlib.import_module(f'.{module_path}', package='google.plugins')

    return module.run(args)
