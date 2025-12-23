#!/usr/bin/env python3
"""
Screenshot tool for macOS that captures windows without activating them.
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

        # Skip windows without owner
        if not owner:
            continue

        result.append({
            'id': window_id,
            'app': owner,
            'title': title
        })

    return result


def find_window_by_app(app_name):
    """Find first window matching application name (case-insensitive)."""
    windows = get_windows()
    app_lower = app_name.lower()

    for window in windows:
        if app_lower in window['app'].lower():
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


def downscale_image(image_path, factor):
    """Downscale image using sips. Factor 0.5 = 50% of original size."""
    try:
        # Get original dimensions
        result = subprocess.run(
            ['sips', '-g', 'pixelWidth', image_path],
            capture_output=True,
            text=True,
            check=True
        )
        width_line = [l for l in result.stdout.split('\n') if 'pixelWidth' in l][0]
        original_width = int(width_line.split(':')[1].strip())

        # Calculate new width
        new_width = int(original_width * factor)

        # Downscale (sips -Z maintains aspect ratio)
        subprocess.run(
            ['sips', '-Z', str(new_width), image_path],
            capture_output=True,
            check=True
        )
        return True
    except (subprocess.CalledProcessError, IndexError, ValueError) as e:
        print(f"Error downscaling image: {e}", file=sys.stderr)
        return False


def convert_to_jpeg(png_path, jpeg_path, max_width=1500, quality=80):
    """Convert PNG to JPEG with resize and compression."""
    try:
        # Resize to max width (maintains aspect ratio)
        subprocess.run(
            ['sips', '-Z', str(max_width), png_path, '--out', jpeg_path],
            capture_output=True,
            check=True
        )

        # Convert to JPEG with quality setting
        subprocess.run(
            ['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', str(quality), jpeg_path],
            capture_output=True,
            check=True
        )

        return True
    except subprocess.CalledProcessError as e:
        print(f"Error converting to JPEG: {e}", file=sys.stderr)
        return False


def output_image_with_base64(image_path):
    """Output image path and base64 data for inline display."""
    import base64

    # Output path
    print(image_path)

    # Output marker
    print("---IMAGE-DATA---")

    # Output base64 encoded image
    try:
        with open(image_path, 'rb') as f:
            image_data = f.read()
            b64_data = base64.b64encode(image_data).decode('utf-8')
            print(b64_data)
    except Exception as e:
        print(f"Error encoding image: {e}", file=sys.stderr)


def main():
    if len(sys.argv) < 2:
        print("Usage: capture.py <app_name> [output_path]")
        print("       capture.py <window_id> [output_path]")
        print("       capture.py --list")
        print("")
        print("Captures screenshot and outputs JPEG with base64 data:")
        print("  • Resized to max 1500px width (maintains aspect ratio)")
        print("  • JPEG quality 80 (~400KB, optimized for LLM)")
        print("  • Outputs file path + base64 encoded image data")
        print("")
        print("Examples:")
        print("  capture.py 'Google Chrome'              # Capture Chrome window")
        print("  capture.py 1411                         # Capture by window ID")
        print("  capture.py 1411 /tmp/my-screenshot.jpg  # Custom output path")
        print("  capture.py --list                       # List all windows")
        sys.exit(1)

    # List windows mode
    if sys.argv[1] == '--list':
        windows = get_windows()

        # Filter out unwanted windows
        filtered_windows = []
        for w in windows:
            # Skip status bar items and other non-windows
            if w['title'] == 'Item-0':
                continue
            # Skip system UI elements
            if w['app'] in ['Dock', 'Control Center', 'Window Server']:
                continue
            filtered_windows.append(w)

        # Group by application
        apps = {}
        for w in filtered_windows:
            app_name = w['app']
            if app_name not in apps:
                apps[app_name] = []
            apps[app_name].append(w)

        # Print grouped by application
        for app_name in sorted(apps.keys()):
            print(f"\n{app_name}")
            print("-" * 80)
            for w in apps[app_name]:
                title = w['title'][:60] if w['title'] else '(no title)'
                print(f"  [{w['id']:<10}] {title}")

        print(f"\nNote: Only showing active tab title for each window")
        sys.exit(0)

    # Parse arguments (simple: app_name/window_id and optional output_path)
    app_name = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else None
    window_id = None

    # Check if first arg is a window ID (numeric)
    if app_name.isdigit():
        window_id = int(app_name)

    # Default output path
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

    if window_id:
        # Capture by window ID
        if not output_path:
            output_path = os.path.join(project_root, 'tmp', f'screenshot-{timestamp}.png')

        os.makedirs(os.path.dirname(output_path), exist_ok=True)

        # Verify window exists
        all_windows = get_windows()
        window_exists = any(w['id'] == window_id for w in all_windows)
        if not window_exists:
            print(f"Error: Window ID {window_id} not found", file=sys.stderr)
            print("Run with --list to see all windows", file=sys.stderr)
            sys.exit(1)

        # Capture
        temp_png_path = output_path
        jpeg_path = output_path.replace('.png', '.jpg')

        if capture_window(window_id, temp_png_path):
            # Convert PNG to JPEG with resize and compression
            if convert_to_jpeg(temp_png_path, jpeg_path):
                # Clean up temporary PNG
                os.remove(temp_png_path)

                # Output path and base64 data
                output_image_with_base64(jpeg_path)
            else:
                sys.exit(1)
        else:
            sys.exit(1)
    else:
        # Single window capture
        if not output_path:
            output_path = os.path.join(project_root, 'tmp', f'screenshot-{timestamp}.png')

        # Ensure output directory exists
        os.makedirs(os.path.dirname(output_path), exist_ok=True)

        # Find window
        window = find_window_by_app(app_name)
        if not window:
            print(f"Error: No window found matching '{app_name}'", file=sys.stderr)
            print("Run with --list to see all windows", file=sys.stderr)
            sys.exit(1)

        # Capture
        temp_png_path = output_path
        jpeg_path = output_path.replace('.png', '.jpg')

        if capture_window(window['id'], temp_png_path):
            # Convert PNG to JPEG with resize and compression
            if convert_to_jpeg(temp_png_path, jpeg_path):
                # Clean up temporary PNG
                os.remove(temp_png_path)

                # Output path and base64 data
                output_image_with_base64(jpeg_path)
            else:
                sys.exit(1)
        else:
            sys.exit(1)


if __name__ == '__main__':
    main()
