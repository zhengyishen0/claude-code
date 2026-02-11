#!/usr/bin/env bash
# md2pdf - Convert Markdown to PDF and HTML with Chinese support
# Usage: md2pdf input.md [output_dir]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSS_FILE="$SCRIPT_DIR/style.css"

if [[ -z "$1" ]]; then
    echo "Usage: md2pdf <input.md> [output_dir]"
    echo "  Output defaults to current directory"
    exit 1
fi

INPUT="$1"
INPUT_DIR="$(dirname "$INPUT")"
OUTPUT_DIR="${2:-$INPUT_DIR}"
BASENAME="$(basename "${INPUT%.md}")"

# Create output dir if not exists
mkdir -p "$OUTPUT_DIR"

HTML_OUT="$OUTPUT_DIR/$BASENAME.html"
PDF_OUT="$OUTPUT_DIR/$BASENAME.pdf"
TMP_HTML="$(mktemp).html"

# Generate HTML with pandoc default style (for viewing)
pandoc "$INPUT" -o "$HTML_OUT" --standalone --metadata title="$BASENAME"

# Inject Chinese font into HTML (only first occurrence)
sed -i '' '0,/body {/s/body {/body { font-family: "PingFang SC", "Hiragino Sans GB", sans-serif;/' "$HTML_OUT"

# Generate PDF with custom CSS
pandoc "$INPUT" -o "$TMP_HTML" --standalone --css="$CSS_FILE" --embed-resources
weasyprint "$TMP_HTML" "$PDF_OUT" 2>/dev/null
rm "$TMP_HTML"

echo "Created:"
echo "  HTML: $HTML_OUT"
echo "  PDF:  $PDF_OUT"
