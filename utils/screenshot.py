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


HELP_TEXT = """screenshot - Background window capture for macOS

USAGE
    screenshot <app_name> [output_path]
    screenshot <window_id> [output_path]
    screenshot --list

DESCRIPTION
    Captures screenshots of windows without activating them using macOS
    window server APIs. Useful for capturing browser automation,
    monitoring background processes, or documentation.

ARGUMENTS
    app_name      Application name to capture (case-insensitive partial match)
                  Examples: "Chrome", "Google Chrome", "Terminal"

    window_id     Numeric window ID (from --list output)

    output_path   Optional output file path (default: ./tmp/screenshot-TIMESTAMP.jpg)

OPTIONS
    --list        List all capturable windows with IDs and titles
    -h, --help    Show this help message

EXAMPLES
    screenshot Chrome
    screenshot "Google Chrome" /tmp/my-screenshot.jpg
    screenshot 12345
    screenshot --list

REQUIREMENTS
    macOS with Python 3 and pyobjc-framework-Quartz
"""


def get_windows():
    """Get list of all on-screen windows with their IDs and info."""
    windows = Quartz.CGWindowListCopyWindowInfo(
        Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
        Quartz.kCGNullWindowID
    )

    result = []
    for window in windows:
        owner = window.get('kCGWindowOwnerName', '')
        title = window.get('kCGWindowName', '')
        window_id = window['kCGWindowNumber']

        if not owner:
            continue

        result.append({
            'id': window_id,
            'app': owner,
            'title': title
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
    """Show list of available windows."""
    windows = get_windows()

    # Filter out unwanted windows
    filtered_windows = []
    for w in windows:
        if w['title'] == 'Item-0':
            continue
        if w['app'] in ['Dock', 'Control Center', 'Window Server']:
            continue
        filtered_windows.append(w)

    for w in filtered_windows:
        title = w['title'] if w['title'] else '(no title)'
        print(f"[{w['id']}] {w['app']} - {title}")


def get_output_dir():
    """Get output directory (PROJECT_DIR/tmp or current dir)."""
    project_dir = os.environ.get('PROJECT_DIR')
    if project_dir:
        return os.path.join(project_dir, 'tmp')
    return os.path.join(os.getcwd(), 'tmp')


def main():
    # Help
    if len(sys.argv) < 2 or sys.argv[1] in ['-h', '--help', 'help']:
        print(HELP_TEXT)
        sys.exit(0)

    # List windows
    if sys.argv[1] == '--list':
        show_list()
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
