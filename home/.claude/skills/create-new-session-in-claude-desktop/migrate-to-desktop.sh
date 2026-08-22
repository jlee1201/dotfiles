#!/usr/bin/env bash
# Convert a live, remote-control-visible child session into a persistent,
# native Claude Desktop sidebar entry: tear down its tmux pane (turning the
# transcript into an orphaned CLI session), then import it via the resume
# deep link. Run ONLY when the user has explicitly asked to migrate/close
# off a child session (e.g. "close off child sessions", "migrate sessions to
# claude desktop") -- never automatically. See rules.md.
#
# Usage: migrate-to-desktop.sh <name> <uuid>
#
# Known bug, confirmed by the user's own testing, 2026-08-20: BOTH this deep-
# link path AND the CLI's own `/desktop` command wipe/generic-title the
# session and don't carry permissions over -- there's no known-good
# alternative that avoids this, so it's accepted as a cost paid only at
# migrate time (not on every child launch, the way the old bootstrap-then-
# deep-link design used to pay it immediately). After this script exits 0:
#   1. Call set_session_title(session_id="local_<uuid>", title="<name>")
#      from the orchestrating agent (MCP tool, not shell-scriptable) --
#      reuse the same <name> the child was launched with so the sidebar
#      label matches what it showed while live.
#   2. Tell the user the session's permission mode defaults to Manual until
#      they click its permission-mode chip in Desktop's UI once it appears
#      -- this skill does not patch that (see learnings.md, 2026-08-20 and
#      2026-08-14: the chip is a live, instant, no-restart fix anyway).
set -euo pipefail

NAME="${1:?Usage: $0 <name> <uuid>}"
UUID="${2:?Usage: $0 <name> <uuid>}"

if tmux has-session -t "$NAME" 2>/dev/null; then
  tmux send-keys -t "$NAME" -l "/exit"
  sleep 0.3
  tmux send-keys -t "$NAME" Enter
  # The deep link recovers an ORPHANED CLI transcript -- firing it while the
  # process still holds the session live is untested territory. Poll for the
  # pane to actually be gone before opening it; hard-kill as a fallback if
  # /exit doesn't land within a few seconds.
  gone=0
  for _ in $(seq 1 15); do
    sleep 1
    tmux has-session -t "$NAME" 2>/dev/null || { gone=1; break; }
  done
  [ "$gone" = 1 ] || tmux kill-session -t "$NAME" >/dev/null 2>&1 || true
else
  echo "No live tmux session named '$NAME' -- transcript is already orphaned (pane closed some other way); proceeding to import it anyway." >&2
fi

open "claude://resume?session=$UUID"
echo "Deep link opened for $UUID." >&2
echo "Now: call set_session_title(session_id=\"local_$UUID\", title=\"$NAME\"), and tell the user to click this session's permission-mode chip in Desktop's UI once it shows up." >&2
