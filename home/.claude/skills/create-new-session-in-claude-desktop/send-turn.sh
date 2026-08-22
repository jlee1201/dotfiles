#!/usr/bin/env bash
# Send another turn into a still-alive child session tmux pane that
# launch-child-session.sh created. Repeatable -- call this as many times as
# the parent wants to keep driving the child directly. Does NOT tear the
# pane down; the child keeps living until you either call this again, run
# migrate-to-desktop.sh, or the human closes it by hand. This is the default
# path for "keep tmux and the session running, I may want to continue
# interacting with the child via the parent" (see rules.md).
#
# Usage: send-turn.sh <name> "<prompt>"
#
# <name> is the tmux session name launch-child-session.sh used (== its -n/
# --remote-control name too).
set -euo pipefail

NAME="${1:?Usage: $0 <name> \"<prompt>\"}"
PROMPT="${2:?Usage: $0 <name> \"<prompt>\"}"

tmux has-session -t "$NAME" 2>/dev/null || {
  echo "No tmux session named '$NAME' -- it may have already been migrated (migrate-to-desktop.sh tears the pane down) or closed by hand. Check with: tmux ls" >&2
  exit 1
}

# Same sentinel-per-name convention as launch-child-session.sh. Remove any
# leftover first -- a stale sentinel here would make the wait loop below
# return instantly and report "done" before this turn even started.
STOP_SENTINEL="/tmp/claude-child-stopmark-${NAME}"
rm -f "$STOP_SENTINEL"

tmux send-keys -t "$NAME" -l "$PROMPT"
sleep 0.3
tmux send-keys -t "$NAME" Enter

status="still-running"
for _ in $(seq 1 300); do
  sleep 2
  if [ -f "$STOP_SENTINEL" ]; then
    status="done"
    break
  fi
done
rm -f "$STOP_SENTINEL"

if [ "$status" = "done" ]; then
  echo "Turn completed in tmux session '$NAME'."
else
  echo "Warning: couldn't confirm the turn finished after 10m -- pane left alive rather than guessing. Check: tmux attach -t $NAME" >&2
  echo "Re-run this script (it will rm the stale sentinel first) once you've confirmed via attach whether it's still genuinely working." >&2
  exit 1
fi
