#!/usr/bin/env python3
"""
screenshot - Background window capture for macOS

Uses PyObjC + Quartz framework to get CGWindowIDs and screencapture CLI.
"""

import subprocess
import sys
import os
from datetime import datetime

try:
    import Quartz
except ImportError:
    print("Error: PyObjC not installed. Run: pip3 install pyobjc-framework-Quartz", file=sys.stderr)
    sys.exit(1)


# Apps that create layer-0 windows but aren't real user windows
UTILITY_APPS = {
    'AutoFill', 'loginwindow', 'ShareSheetUI', 'Maccy', 'Jitouch',
    'TheBoringNotch', 'Ice', 'Clop', 'WeatherMenu', 'Homerow',
    'FreeGecko', 'ProNotes', 'Voca', 'Open and Save Panel Service',
}

HELP_TEXT = """screenshot - Background window capture for macOS

USAGE
    screenshot                              List available windows
    screenshot <app-name|window-id> [path]  Capture a window

ARGUMENTS
    app-name      Application name (case-insensitive partial match)
    window-id     Numeric window ID from the list
    path          Output path (default: ./tmp/screenshot-TIMESTAMP.jpg)

EXAMPLES
    screenshot                    # List windows
    screenshot Chrome             # Capture Chrome window
    screenshot 12345 out.png      # Capture by ID
"""


def get_windows():
    """Get list of all capturable windows with their IDs and info."""
    windows = Quartz.CGWindowListCopyWindowInfo(
        Quartz.kCGWindowListOptionAll | Quartz.kCGWindowListExcludeDesktopElements,
        Quartz.kCGNullWindowID
    )

    result = []
    for window in windows:
        owner = window.get('kCGWindowOwnerName', '')
        title = window.get('kCGWindowName', '')
        window_id = window['kCGWindowNumber']
        layer = window.get('kCGWindowLayer', 0)
        bounds = window.get('kCGWindowBounds', {})

        if not owner:
            continue

        # Only include normal windows (layer 0)
        # Higher layers are overlays, menu bar items, etc.
        if layer != 0:
            continue

        # Filter out utility apps (menu bar, overlays, etc.)
        if owner in UTILITY_APPS:
            continue

        # Filter out tiny windows (helper windows, 1x1 placeholders)
        width = bounds.get('Width', 0)
        height = bounds.get('Height', 0)
        if width < 100 or height < 100:
            continue

        result.append({
            'id': window_id,
            'app': owner,
            'title': title,
            'bounds': bounds,
            'on_screen': window.get('kCGWindowIsOnscreen', False)
        })

    return result


def find_window_by_app(app_name):
    """Find first window matching application name with fuzzy matching (case-insensitive)."""
    windows = get_windows()
    app_lower = app_name.lower()

    # First try exact substring match
    for window in windows:
        if app_lower in window['app'].lower():
            return window

    # Then try fuzzy match: all characters in order
    for window in windows:
        window_name = window['app'].lower()
        pos = 0
        for char in app_lower:
            pos = window_name.find(char, pos)
            if pos == -1:
                break
            pos += 1
        else:
            return window

    return None


def find_all_windows_by_app(app_name):
    """Find all windows matching application name (case-insensitive)."""
    windows = get_windows()
    app_lower = app_name.lower()

    matching = []
    for window in windows:
        if app_lower in window['app'].lower():
            matching.append(window)

    return matching


def capture_window(window_id, output_path):
    """Capture window by CGWindowID using screencapture."""
    try:
        subprocess.run(
            ['screencapture', '-l', str(window_id), '-o', output_path],
            check=True,
            capture_output=True
        )
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error capturing window: {e.stderr.decode()}", file=sys.stderr)
        return False


def convert_to_jpeg(png_path, jpeg_path, max_width=1500, quality=80):
    """Convert PNG to JPEG with resize and compression."""
    try:
        subprocess.run(
            ['sips', '-Z', str(max_width), png_path, '--out', jpeg_path],
            capture_output=True,
            check=True
        )
        subprocess.run(
            ['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', str(quality), jpeg_path],
            capture_output=True,
            check=True
        )
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error converting to JPEG: {e}", file=sys.stderr)
        return False


def show_list():
    """Show list of available windows with usage hint."""
    windows = get_windows()

    # Sort: on-screen windows first
    windows.sort(key=lambda w: (not w.get('on_screen', False), w['app']))

    for w in windows:
        title = w['title'] if w['title'] else '(no title)'
        bounds = w.get('bounds', {})
        size = f"{int(bounds.get('Width', 0))}x{int(bounds.get('Height', 0))}"
        marker = '' if w.get('on_screen') else ' [other space]'
        print(f"[{w['id']}] {w['app']} - {title} ({size}){marker}")

    print()
    print("Usage: screenshot <app-name|window-id> [output-path]")


def get_output_dir():
    """Get output directory (PROJECT_DIR/tmp or current dir)."""
    project_dir = os.environ.get('PROJECT_DIR')
    if project_dir:
        return os.path.join(project_dir, 'tmp')
    return os.path.join(os.getcwd(), 'tmp')


def main():
    # No args: show window list
    if len(sys.argv) < 2:
        show_list()
        sys.exit(0)

    # Help
    if sys.argv[1] in ['-h', '--help', 'help']:
        print(HELP_TEXT)
        sys.exit(0)

    # Parse arguments
    target = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else None

    # Default output path
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    output_dir = get_output_dir()

    if not output_path:
        output_path = os.path.join(output_dir, f'screenshot-{timestamp}.png')

    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    # Check if target is a window ID (numeric)
    if target.isdigit():
        window_id = int(target)
        all_windows = get_windows()
        if not any(w['id'] == window_id for w in all_windows):
            print(f"Window ID {window_id} not found", file=sys.stderr)
            print("\nAvailable windows:")
            show_list()
            sys.exit(1)
    else:
        # Find by app name
        all_matches = find_all_windows_by_app(target)
        if len(all_matches) > 1:
            print(f"Multiple windows found matching '{target}'", file=sys.stderr)
            print("\nMatching windows:")
            for w in all_matches:
                title = w['title'] if w['title'] else '(no title)'
                print(f"  [{w['id']}] {w['app']} - {title}")
            sys.exit(1)

        window = find_window_by_app(target)
        if not window:
            print(f"No window found matching '{target}'", file=sys.stderr)
            print("\nAvailable windows:")
            show_list()
            sys.exit(1)

        window_id = window['id']

    # Capture
    temp_png_path = output_path
    jpeg_path = output_path.replace('.png', '.jpg')

    if capture_window(window_id, temp_png_path):
        if convert_to_jpeg(temp_png_path, jpeg_path):
            os.remove(temp_png_path)
            print(f"Screenshot saved: {jpeg_path}")
            print("Use Read tool to view the image.")
        else:
            sys.exit(1)
    else:
        sys.exit(1)


if __name__ == '__main__':
    main()
