#!/usr/bin/env bash
# Poll for a child session's CURRENT turn to finish, then print one
# human-readable notification line and exit. This script does the "polls
# mechanically" part of "background task that polls, then notifies the
# parent" -- but polling alone doesn't get a message into the parent chat.
# THE CALLER MUST invoke this script as its OWN backgrounded tool call (e.g.
# Bash with run_in_background: true) right after launch-child-session.sh (or
# send-turn.sh) returns -- the harness notifies the agent when a backgrounded
# call exits, which is what actually surfaces this in the parent conversation.
# A bare `... & disown`-style shell background process has no such channel;
# don't try to build one inside this script. See rules.md / learnings.md,
# 2026-08-21.
#
# Usage: watch-child-turn.sh <name> <uuid>
#
# Polls the same `/tmp/claude-child-stopmark-<name>` Stop-hook sentinel
# convention launch-child-session.sh/send-turn.sh use. On the SAME loop (not
# gated behind the sentinel) also checks the transcript for a bare
# "Login expired" turn, since a login-expired session never fires the Stop
# hook at all (see learnings.md, 2026-08-13) -- without this independent
# check, a dead session would poll silently for the full timeout below.
#
# Exit 0 with a "finished" message once the sentinel fires (also flags
# login-expired if that's what actually happened). Exit 0 with a distinct
# "login-expired" message if that's detected before the sentinel ever fires.
# Exit 1 if the tmux pane disappears without the sentinel ever firing (most
# likely: migrated or closed by hand while this was polling -- nothing left
# to notify about). Exit 0 with a "still running" message after a generous
# 4-hour timeout rather than polling forever.
set -euo pipefail

NAME="${1:?Usage: $0 <name> <uuid>}"
UUID="${2:?Usage: $0 <name> <uuid>}"
STOP_SENTINEL="/tmp/claude-child-stopmark-${NAME}"

transcript=$(find "$HOME/.claude/projects" -maxdepth 2 -name "${UUID}.jsonl" 2>/dev/null | head -1 || true)

MAX=14400  # 4 hours
POLL=3
START=$SECONDS

while true; do
  if [ -f "$STOP_SENTINEL" ]; then
    rm -f "$STOP_SENTINEL"
    if [ -n "$transcript" ] && grep -q "Login expired" "$transcript" 2>/dev/null; then
      echo "Child session '$NAME' (uuid $UUID) hit a login-expired error -- nothing useful happened. tmux attach -t $NAME and run /login by hand, then re-send the task with send-turn.sh."
      exit 0
    fi
    echo "Child session '$NAME' (uuid $UUID) finished its current turn. Ask the user if they want to migrate it to Desktop: ~/.claude/skills/create-new-session-in-claude-desktop/migrate-to-desktop.sh $NAME $UUID"
    exit 0
  fi

  if [ -n "$transcript" ] && grep -q "Login expired" "$transcript" 2>/dev/null; then
    echo "Child session '$NAME' (uuid $UUID) hit a login-expired error -- nothing useful happened. tmux attach -t $NAME and run /login by hand, then re-send the task with send-turn.sh."
    exit 0
  fi

  if ! tmux has-session -t "$NAME" 2>/dev/null; then
    echo "Child session '$NAME' (uuid $UUID) is no longer live -- its pane closed before this turn's Stop-hook fired (likely migrated or closed by hand while this watcher was running). Nothing further to notify."
    exit 1
  fi

  if [ $(( SECONDS - START )) -ge "$MAX" ]; then
    echo "Child session '$NAME' (uuid $UUID) is still running after 4 hours -- not necessarily a problem, but worth checking: tmux attach -t $NAME"
    exit 0
  fi

  sleep "$POLL"
done
