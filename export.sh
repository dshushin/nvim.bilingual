#!/bin/bash
# export.sh — Export bilingual markdown to PDF and/or DOCX
# Usage:
#   ./export.sh document.md           # both PDF + DOCX
#   ./export.sh document.md --pdf     # PDF only
#   ./export.sh document.md --docx    # DOCX only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILTER="$SCRIPT_DIR/filter/bilingual.lua"
TEMPLATE="$SCRIPT_DIR/templates/bilingual.latex"
OUTPUT_DIR="$HOME/Documents/bilingual-exports"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <file.md> [--pdf|--docx]"
  exit 1
fi

INPUT="$1"
FORMAT="${2:-}"

if [ ! -f "$INPUT" ]; then
  echo "Error: file not found: $INPUT"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
BASENAME="$(basename "$INPUT" .md)"

do_pdf() {
  echo "Exporting PDF..."
  pandoc "$INPUT" \
    --lua-filter="$FILTER" \
    --template="$TEMPLATE" \
    --pdf-engine=xelatex \
    -V mainfont="PT Serif" \
    -V sansfont="Helvetica Neue" \
    -V monofont="Menlo" \
    -o "$OUTPUT_DIR/$BASENAME.pdf"
  echo "  -> $OUTPUT_DIR/$BASENAME.pdf"
}

do_docx() {
  echo "Exporting DOCX..."
  pandoc "$INPUT" \
    --lua-filter="$FILTER" \
    -o "$OUTPUT_DIR/$BASENAME.docx"
  echo "  -> $OUTPUT_DIR/$BASENAME.docx"
}

case "$FORMAT" in
  --pdf)  do_pdf ;;
  --docx) do_docx ;;
  *)      do_pdf; do_docx ;;
esac

echo "Done."
