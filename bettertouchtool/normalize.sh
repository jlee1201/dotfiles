#!/usr/bin/env bash
# Normalize a BetterTouchTool preset export for version control.
#
# Strips fields that change on every BTT launch but are not meaningful config:
#   - BTTNumberOfStarts (launch counter)
#   - BTTSavedMousePosition (last mouse coords)
#   - BTTLastClamshellState (lid open/closed at export time)
#   - BTTDidRegisterForUpdateStats (BTT version string)
#   - BTTSelectedKeyboardTabIndex (UI tab state)
#
# Usage:
#   ./normalize.sh                            # uses ~/Downloads/Default.bttpreset
#   ./normalize.sh /path/to/export.bttpreset
#
# Output: writes cleaned JSON to ./btt-config.json (alongside this script).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT="${1:-$HOME/Downloads/Default.bttpreset}"
OUTPUT="$SCRIPT_DIR/btt-config.json"

if [[ ! -f "$INPUT" ]]; then
  echo "ERROR: input file not found: $INPUT" >&2
  echo "Usage: $0 [path-to-bttpreset]" >&2
  exit 1
fi

if ! python3 -m json.tool < "$INPUT" > /dev/null 2>&1; then
  echo "ERROR: input is not valid JSON: $INPUT" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq not installed. brew install jq" >&2
  exit 1
fi

jq '
  del(.BTTGeneralSettings.BTTNumberOfStarts) |
  del(.BTTGeneralSettings.BTTSavedMousePosition) |
  del(.BTTGeneralSettings.BTTLastClamshellState) |
  del(.BTTGeneralSettings.BTTDidRegisterForUpdateStats) |
  del(.BTTGeneralSettings.BTTSelectedKeyboardTabIndex)
' "$INPUT" > "$OUTPUT"

echo "Normalized:"
echo "  in:  $INPUT"
echo "  out: $OUTPUT"
echo
echo "Stripped noise fields. Review with:"
echo "  cd $(dirname "$SCRIPT_DIR") && git diff $(basename "$SCRIPT_DIR")/btt-config.json"
