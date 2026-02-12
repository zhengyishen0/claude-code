#!/bin/bash
set -euo pipefail

# Extract YouTube transcript using youtube-transcript-api (Python)
# Fastest and most reliable option based on testing

LANG="en"
OUTPUT=""
FORMAT="text"

usage() {
    echo "Usage: yt-transcript [options] <video_id_or_url>"
    echo ""
    echo "Options:"
    echo "  -l, --lang <code>    Language code (default: en)"
    echo "  -o, --output <file>  Save to file instead of stdout"
    echo "  --json               Output as JSON with timestamps"
    echo "  -h, --help           Show this help"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--lang)
            LANG="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT="$2"
            shift 2
            ;;
        --json)
            FORMAT="json"
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            VIDEO="$1"
            shift
            ;;
    esac
done

if [[ -z "${VIDEO:-}" ]]; then
    echo "Error: No video ID or URL provided" >&2
    usage
fi

# Extract video ID from URL if needed
VIDEO_ID="$VIDEO"
if [[ "$VIDEO" == *"youtube.com"* ]] || [[ "$VIDEO" == *"youtu.be"* ]]; then
    # Extract ID from various URL formats
    if [[ "$VIDEO" == *"v="* ]]; then
        VIDEO_ID=$(echo "$VIDEO" | sed 's/.*v=\([^&]*\).*/\1/')
    elif [[ "$VIDEO" == *"youtu.be/"* ]]; then
        VIDEO_ID=$(echo "$VIDEO" | sed 's/.*youtu.be\/\([^?]*\).*/\1/')
    fi
fi

# Ensure youtube-transcript-api is installed
if ! python3 -c "import youtube_transcript_api" 2>/dev/null; then
    echo "Installing youtube-transcript-api..." >&2
    pip3 install -q youtube-transcript-api
fi

# Add Python user bin to PATH if needed
export PATH="$PATH:$HOME/Library/Python/3.9/bin:$HOME/.local/bin"

# Run the command
if [[ "$FORMAT" == "json" ]]; then
    CMD="youtube_transcript_api $VIDEO_ID --languages $LANG --format json"
else
    CMD="youtube_transcript_api $VIDEO_ID --languages $LANG --format text"
fi

if [[ -n "$OUTPUT" ]]; then
    $CMD 2>/dev/null > "$OUTPUT"
    echo "Saved to $OUTPUT"
else
    $CMD 2>/dev/null
fi
