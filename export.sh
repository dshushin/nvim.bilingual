#!/bin/bash
# export.sh — Export bilingual markdown to PDF and/or DOCX
# Usage:
#   ./export.sh document.md                # both PDF + DOCX (redline if CriticMarkup present)
#   ./export.sh document.md --pdf          # PDF only
#   ./export.sh document.md --docx         # DOCX only
#   ./export.sh document.md --accept       # both, accept all changes (clean version)
#   ./export.sh document.md --pdf --accept # PDF only, clean version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILTER="$SCRIPT_DIR/filter/bilingual.lua"
CRITIC_FILTER="$SCRIPT_DIR/filter/criticmarkup.lua"
TEMPLATE="$SCRIPT_DIR/templates/bilingual.latex"
OUTPUT_DIR="$HOME/Documents/bilingual-exports"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <file.md> [--pdf|--docx] [--accept]"
  exit 1
fi

INPUT="$1"
shift

DO_PDF=false
DO_DOCX=false
CRITIC_MODE="redline"

for arg in "$@"; do
  case "$arg" in
    --pdf)    DO_PDF=true ;;
    --docx)   DO_DOCX=true ;;
    --accept) CRITIC_MODE="accept" ;;
  esac
done

# If neither --pdf nor --docx specified, do both
if ! $DO_PDF && ! $DO_DOCX; then
  DO_PDF=true
  DO_DOCX=true
fi

if [ ! -f "$INPUT" ]; then
  echo "Error: file not found: $INPUT"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
BASENAME="$(basename "$INPUT" .md)"

do_pdf() {
  echo "Exporting PDF${1:+ ($1)}..."
  pandoc "$INPUT" \
    -f markdown-strikeout-subscript \
    -M critic-mode="$CRITIC_MODE" \
    --lua-filter="$CRITIC_FILTER" \
    --lua-filter="$FILTER" \
    --template="$TEMPLATE" \
    --pdf-engine=lualatex \
    -V mainfont="PT Serif" \
    -V sansfont="Helvetica Neue" \
    -V monofont="Menlo" \
    -o "$OUTPUT_DIR/$BASENAME.pdf"
  echo "  -> $OUTPUT_DIR/$BASENAME.pdf"
}

do_docx() {
  echo "Exporting DOCX${1:+ ($1)}..."
  pandoc "$INPUT" \
    -f markdown-strikeout-subscript \
    -M critic-mode="$CRITIC_MODE" \
    --lua-filter="$CRITIC_FILTER" \
    --lua-filter="$FILTER" \
    -o "$OUTPUT_DIR/$BASENAME.docx"
  echo "  -> $OUTPUT_DIR/$BASENAME.docx"
}

MODE_LABEL=""
if [ "$CRITIC_MODE" = "accept" ]; then
  MODE_LABEL="clean"
fi

$DO_PDF  && do_pdf "$MODE_LABEL"
$DO_DOCX && do_docx "$MODE_LABEL"

echo "Done."
