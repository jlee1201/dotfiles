#!/usr/bin/env bash
# Verify Powerlevel10k prompt changes (home/.p10k.zsh) in a REAL rendered
# terminal, without needing to manually screenshot iTerm and describe it back.
#
# Why this exists: during the last big .p10k.zsh customization session,
# `expect`/`script` + stripping ANSI escapes proved UNRELIABLE for verifying
# prompt LAYOUT (indentation, frame characters, line placement, stray icons).
# p10k's transient-prompt collapse trick uses cursor-based redraws that a
# stripped/linear escape dump can't represent correctly - it can tell you
# "no unexpected text appeared" but not "this is what it actually looks
# like". `tmux capture-pane -p` resolves cursor movements into the true
# final screen state and IS reliable for both purposes. See
# .cursor/troubleshooting.mdc and .cursor/architecture-decisions.mdc
# ("Powerlevel10k Custom Timing Prompt") for the full story and the specific
# bugs this would have caught sooner.
#
# Usage:
#   scripts/test-p10k-prompt.sh                        # default command sequence
#   scripts/test-p10k-prompt.sh 'sleep 2' 'echo hi'    # your own commands
#   scripts/test-p10k-prompt.sh --delay 5 'sleep 3'    # custom per-command delay (seconds)
#
# Always sources ~/.p10k.zsh first (so uncommitted edits take effect without
# a new shell), runs each command with a delay after it, then prints:
#   1. The final rendered layout (plain text, cursor-accurate).
#   2. A scan of the raw capture for Nerd Font Private-Use-Area glyphs -
#      the signature of the "orphaned icon" bug class (renders as a small
#      glyph in one terminal font, a tofu box in another, invisible in a
#      third - always investigate with this scan, not by squinting at a
#      screenshot).

set -euo pipefail

SESSION="p10ktest-$$"
DELAY=3
COMMANDS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --delay)
      DELAY="$2"
      shift 2
      ;;
    --session-name)
      SESSION="$2"
      shift 2
      ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      COMMANDS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#COMMANDS[@]} -eq 0 ]]; then
  # A short (<1s) command, a long (>=1s) command, and a final short one -
  # exercises both branches of the duration-range logic in one run.
  COMMANDS=('echo hi' 'sleep 2' 'echo done')
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux is required (brew install tmux)" >&2
  exit 1
fi

cleanup() { tmux kill-session -t "$SESSION" 2>/dev/null || true; }
trap cleanup EXIT

tmux new-session -d -s "$SESSION" -x 200 -y 50 "zsh -i"
sleep 1
tmux send-keys -t "$SESSION" "source ~/.p10k.zsh" Enter
sleep 3

for cmd in "${COMMANDS[@]}"; do
  tmux send-keys -t "$SESSION" "$cmd" Enter
  sleep "$DELAY"
done

plain=$(mktemp)
raw=$(mktemp)
trap 'rm -f "$plain" "$raw"; cleanup' EXIT
tmux capture-pane -t "$SESSION" -p > "$plain"
tmux capture-pane -t "$SESSION" -p -e > "$raw"

echo "=== Rendered layout (cursor-accurate) ==="
cat -n "$plain"

echo
echo "=== Stray Nerd Font icon scan (Private Use Area U+E000-U+F8FF) ==="
python3 - "$raw" << 'PYEOF'
import sys

data = open(sys.argv[1], "rb").read()
found = []
i = 0
while i < len(data) - 2:
    b0, b1, b2 = data[i], data[i + 1], data[i + 2]
    if 0xE0 <= b0 <= 0xEF and 0x80 <= b1 <= 0xBF and 0x80 <= b2 <= 0xBF:
        cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
        if 0xE000 <= cp <= 0xF8FF:
            found.append((i, cp))
    i += 1

if not found:
    print("(none found)")
else:
    for off, cp in found:
        ctx = data[max(0, off - 30):off + 10]
        print(f"  offset {off}: U+{cp:04X}  context={ctx!r}")
    print(
        f"\n{len(found)} glyph(s) found - eyeball each `context`: a legitimate "
        "one sits adjacent to real segment content (a directory name, a git "
        "branch, another cap glyph); an orphaned one sits next to only "
        "whitespace or background-color codes with nothing to visually "
        "transition to/from."
    )
PYEOF
