#!/usr/bin/env bash
# Launch a new Claude Code child session inside a tmux pane, visible LIVE in
# Claude Desktop's sidebar via the CLI's own remote-control mechanism -- no
# deep-link import, no registry write, no restart. The pane stays alive
# indefinitely after the task completes; the parent can send more turns via
# send-turn.sh, or convert it into a persistent native Desktop session via
# migrate-to-desktop.sh once explicitly told to (see rules.md).
#
# Confirmed empirically, 2026-08-20: ANY interactive `claude` process running
# in a tmux pane shows up live in Desktop's sidebar (grouped by cwd; "Other"
# if cwd resolution fails, e.g. underscore-heavy scratch paths) -- no -n, no
# --remote-control, and no deep link are needed for bare visibility. -n and
# --remote-control <name> each INDEPENDENTLY set the display name shown
# (verified: tested one flag at a time, both worked identically for naming).
# --remote-control also opens a claude.ai/code phone/web control URL for that
# session -- included below per user preference even though it isn't needed
# for Desktop-sidebar visibility on its own.
#
# This mechanism is DIFFERENT from, and does not write to, the persisted
# local registry (`claude-code-sessions/*/*/local_<uuid>.json`) that
# `claude-desktop-internals` and this skill's old bootstrap-session.sh/
# deliver-task.sh targeted: get_session/list_sessions (MCP) return nothing
# for a remote-control-visible session that's never been migrated. Killing
# the tmux pane (or the underlying claude process) makes the sidebar entry
# disappear immediately -- confirmed directly by the user. See learnings.md,
# 2026-08-20, for the full investigation and why the old two-phase
# bootstrap+deep-link design was replaced by this one.
#
# Usage: launch-child-session.sh <cwd>|--same-project <name> "<task prompt>"
#
# <name> is used for ALL of: -n, --remote-control, and the tmux session name
# itself -- kept identical on purpose so the sidebar label, prompt-box label,
# terminal title, and the handle you pass to send-turn.sh/migrate-to-desktop.sh
# all match. Must not collide with an already-running tmux session name.
#
# RETURNS FAST -- does NOT wait for the task to finish. Confirmed empirically
# (2026-08-21) that the transcript .jsonl file exists within ~1s of sending a
# turn, so this script only waits long enough to confirm the child is alive
# and locate its UUID (a few seconds), then returns. Prints two lines on
# stdout: the new session's transcript UUID, then the fixed word "launched".
#
# Immediately after this returns, kick off watch-child-turn.sh <name> <uuid>
# as YOUR OWN backgrounded tool call (e.g. Bash with run_in_background: true)
# -- see rules.md step 2. That is what actually notifies the parent chat
# when the child's first round finishes; this script deliberately does not
# wait for that itself, and a plain shell background process can't notify
# the chat on its own.
#
# Keep <name> (== the tmux session name) and the UUID; both are needed for
# send-turn.sh / migrate-to-desktop.sh / watch-child-turn.sh.
set -euo pipefail

CWD="${1:?Usage: $0 <cwd>|--same-project <name> \"<task prompt>\"}"
NAME="${2:?Usage: $0 <cwd>|--same-project <name> \"<task prompt>\"}"
TASK_PROMPT="${3:?Usage: $0 <cwd>|--same-project <name> \"<task prompt>\"}"

# --- Resolve the calling session's own registry entry once, up front ---
# Ground truth for cwd resolution, model/effort/permissionMode inheritance,
# AND the parent-context prefix below -- the calling session's own live
# registry entry at claude-code-sessions/*/*/local_<CLAUDE_CODE_HOST_SESSION_ID>.json.
# Deliberately not $PWD: it drifts (worktrees, submodules, scratchpad dirs)
# and isn't a safe stand-in for "the project the calling session is grouped
# under in Desktop's sidebar." See learnings.md, 2026-08-17 (1361-session audit).
HOST_REG=""
HOST_CWD=""
HOST_UUID=""
if [ -n "${CLAUDE_CODE_HOST_SESSION_ID:-}" ]; then
  HOST_UUID="${CLAUDE_CODE_HOST_SESSION_ID#local_}"
  desk_dir="$HOME/Library/Application Support/Claude/claude-code-sessions"
  HOST_REG=$(find "$desk_dir" -maxdepth 3 -name "local_${HOST_UUID}.json" 2>/dev/null | head -1 || true)
  if [ -n "$HOST_REG" ]; then
    HOST_CWD=$(python3 -c "import json; print(json.load(open('$HOST_REG')).get('cwd') or '')" 2>/dev/null || true)
  fi
fi

if [ "$CWD" = "--same-project" ]; then
  [ -n "$HOST_CWD" ] || { echo "--same-project requires CLAUDE_CODE_HOST_SESSION_ID's registry entry (with a cwd), which wasn't found -- pass an explicit <cwd> instead" >&2; exit 1; }
  CWD="$HOST_CWD"
  echo "Resolved --same-project to: $CWD" >&2
fi

[ -d "$CWD" ] || { echo "cwd does not exist: $CWD" >&2; exit 1; }
command -v tmux >/dev/null || { echo "tmux not found" >&2; exit 1; }
command -v claude >/dev/null || { echo "claude CLI not found on PATH" >&2; exit 1; }
tmux has-session -t "$NAME" 2>/dev/null && { echo "A tmux session named '$NAME' already exists -- pick a different <name>" >&2; exit 1; }

STOP_SENTINEL="/tmp/claude-child-stopmark-${NAME}"
rm -f "$STOP_SENTINEL"

fail() {
  echo "$1" >&2
  tmux kill-session -t "$NAME" >/dev/null 2>&1 || true
  rm -f "$STOP_SENTINEL"
  exit 1
}

# --- Inherit model/effort/permission-mode from the calling session ---
# Still needed even though nothing gets persisted to a registry entry now:
# this is what lets a tool-approval mid-task not hang forever via send-keys
# with no human present to click "yes." -n/--remote-control use the same
# <name> so every Desktop-visible label matches.
CLAUDE_CLI_ARGS=(-n "$NAME" --remote-control "$NAME")
PARENT_TITLE=""
if [ -n "$HOST_REG" ]; then
  inherited=$(python3 -c "
import json
d = json.load(open('$HOST_REG'))
print(d.get('model') or '')
print(d.get('effort') or '')
print(d.get('permissionMode') or '')
print(d.get('title') or '')
" 2>/dev/null || true)
  h_model=$(sed -n '1p' <<<"$inherited")
  h_effort=$(sed -n '2p' <<<"$inherited")
  h_mode=$(sed -n '3p' <<<"$inherited")
  PARENT_TITLE=$(sed -n '4p' <<<"$inherited")
  inherited_args=()
  [ -n "$h_model" ] && inherited_args+=(--model "$h_model")
  [ -n "$h_effort" ] && inherited_args+=(--effort "$h_effort")
  [ -n "$h_mode" ] && inherited_args+=(--permission-mode "$h_mode")
  if [ "${#inherited_args[@]}" -gt 0 ]; then
    CLAUDE_CLI_ARGS+=("${inherited_args[@]}")
    echo "Inheriting from calling session: ${inherited_args[*]}" >&2
  fi
else
  echo "No calling-session registry found -- new session uses CLI defaults (likely Manual permission mode)." >&2
fi
[ -n "$PARENT_TITLE" ] || PARENT_TITLE=$(basename "$HOST_CWD" 2>/dev/null || true)
[ -n "$PARENT_TITLE" ] || PARENT_TITLE="an untitled parent session"

# --- Bring in the calling project's context when working somewhere else ---
if [ -n "$HOST_CWD" ] && [ "$CWD" != "$HOST_CWD" ] && [ -z "${CHILD_NO_ADD_DIR:-}" ]; then
  CLAUDE_CLI_ARGS+=(--add-dir "$HOST_CWD")
  echo "Adding calling project as extra context: --add-dir $HOST_CWD" >&2
fi
# --- Grant access to a work directory distinct from this session's own cwd ---
# Same worktree pattern as the old bootstrap-session.sh: pair with
# --same-project for <cwd> (correct sidebar grouping from birth) and set
# CHILD_EXTRA_DIR to the worktree path instead of pointing <cwd> at it
# directly. The task prompt must still explicitly say to work in that
# directory -- --add-dir only grants access, not intent.
if [ -n "${CHILD_EXTRA_DIR:-}" ]; then
  CLAUDE_CLI_ARGS+=(--add-dir "$CHILD_EXTRA_DIR")
  echo "Granting access to extra work directory: --add-dir $CHILD_EXTRA_DIR" >&2
fi

# --- Turn-completion signal: a Stop hook, not pane-render inference ---
# Same mechanism as the old bootstrap-session.sh/deliver-task.sh -- confirmed
# live, 2026-08-20, that it still fires correctly on a session launched with
# -n/--remote-control (2s turnaround in testing). See learnings.md for why
# render-diffing/busy-text matching were dead ends.
STOP_HOOK_CMD='input=$(cat); if printf %s "$input" | grep -q agent_type; then exit 0; fi; touch '"$STOP_SENTINEL"
STOP_HOOK_SETTINGS=$(python3 -c "
import json, sys
print(json.dumps({'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': sys.argv[1]}]}]}}))
" "$STOP_HOOK_CMD")
CLAUDE_CLI_ARGS+=(--settings "$STOP_HOOK_SETTINGS")

claude_cmd="claude"
for arg in "${CLAUDE_CLI_ARGS[@]}"; do
  claude_cmd+=" $(printf '%q' "$arg")"
done

# Snapshot existing transcripts for this cwd *before* launching, so the new
# one can be identified by set difference -- not `ls -t | head -1` (breaks
# whenever another live session shares this cwd and writes concurrently;
# confirmed incident in learnings.md that clobbered a real session's title).
enc=$(python3 -c "import sys; print(sys.argv[1].replace('/', '-').replace('.', '-').replace('_', '-'))" "$CWD")
dir="$HOME/.claude/projects/$enc"
before_snapshot=""
[ -d "$dir" ] && before_snapshot=$(ls "$dir"/*.jsonl 2>/dev/null || true)

tmux new-session -d -s "$NAME" -c "$CWD" "$claude_cmd"

# First launch in a never-used cwd shows a one-time trust prompt. Dismiss it,
# then wait for the REPL's idle prompt. NOTE: the prompt line ends in a
# NON-BREAKING SPACE (U+00A0), not ASCII -- match `^❯` only, never `^❯ *$`.
ready=0
for _ in $(seq 1 30); do
  sleep 1
  out=$(tmux capture-pane -t "$NAME" -p 2>/dev/null || true)
  if echo "$out" | grep -q "trust this folder"; then
    tmux send-keys -t "$NAME" Enter
  fi
  if echo "$out" | grep -qE '^❯'; then
    ready=1
    break
  fi
done
[ "$ready" = 1 ] || fail "REPL never became ready -- inspect with: tmux attach -t $NAME"

# --- Build the first turn: parent-context prefix + the real task, sent as ONE turn ---
# No separate fast/seed phase in this design -- naming and Desktop visibility
# already happen automatically via -n/--remote-control, so there's nothing
# left to gate behind a throwaway turn. The prefix gives enough identifying
# info that a LATER round of this same child (or a human) can go read the
# parent's own transcript directly on disk if it turns out to need context
# it wasn't given up front -- deliberately not wired to any new cross-session
# mechanism (agentbus, MCP, etc.) per user preference, 2026-08-20.
if [ -n "$HOST_UUID" ] && [ -n "$HOST_CWD" ]; then
  host_enc=$(python3 -c "import sys; print(sys.argv[1].replace('/', '-').replace('.', '-').replace('_', '-'))" "$HOST_CWD")
  PARENT_CONTEXT="You are a session launched from parent session '${PARENT_TITLE}' (id ${HOST_UUID}, transcript at ~/.claude/projects/${host_enc}/${HOST_UUID}.jsonl, project ${HOST_CWD}). If you need context that wasn't included in your task below, you can read that transcript directly, or state exactly what's missing in your response so the human operator can relay it in a follow-up turn."
else
  PARENT_CONTEXT="You are a session launched from parent session '${PARENT_TITLE}'. If you need context that wasn't included in your task below, state exactly what's missing in your response so the human operator can relay it in a follow-up turn."
fi
FULL_PROMPT="${PARENT_CONTEXT}

Your task: ${TASK_PROMPT}"

tmux send-keys -t "$NAME" -l "$FULL_PROMPT"
sleep 0.3
tmux send-keys -t "$NAME" Enter

# --- Locate the new transcript FAST -- do not wait for the turn to finish ---
# Confirmed empirically, 2026-08-21: the transcript .jsonl file exists within
# ~1s of sending a turn (the session-init/bridge-session lines are written
# immediately, well before the assistant's reply, let alone the Stop hook).
# So there's no need to block this script on the task's own completion --
# that wait moves to watch-child-turn.sh, run as the CALLER's own backgrounded
# tool call (see rules.md) so the harness can actually deliver a completion
# notification into the parent chat, which a plain shell background process
# cannot do on its own. This script's job is just: confirm the child is
# genuinely alive and return its UUID quickly.
sid=""
for _ in $(seq 1 20); do
  sleep 1
  after_snapshot=""
  [ -d "$dir" ] && after_snapshot=$(ls "$dir"/*.jsonl 2>/dev/null || true)
  new_files=$(comm -13 <(sort <<<"$before_snapshot") <(sort <<<"$after_snapshot") 2>/dev/null || true)
  new_count=$(grep -c . <<<"$new_files" || true)
  if [ "$new_count" = 1 ] && [ -n "$new_files" ]; then
    sid=$(basename "$new_files" .jsonl)
    break
  elif [ "$new_count" -gt 1 ]; then
    echo "Warning: multiple new transcripts appeared in $dir -- picking the newest by mtime, but verify with: grep -l '<unique text from your prompt>' $dir/*.jsonl" >&2
    newest="" newest_mtime=0
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
      if [ "$mtime" -gt "$newest_mtime" ]; then newest_mtime=$mtime; newest=$f; fi
    done <<<"$new_files"
    [ -n "$newest" ] && sid=$(basename "$newest" .jsonl)
    break
  fi
done
[ -n "$sid" ] || fail "Could not locate the new transcript under $dir within 20s -- inspect with: tmux attach -t $NAME"

# --- Record this child in a per-parent manifest for later bulk discovery ---
# ("migrate/close off child sessions" needs to enumerate what's alive).
# Deliberately dumb: one JSON line per launch, no status field, no attempt to
# track alive/migrated here -- migrate-to-desktop.sh (and whoever reads this
# file) must treat `tmux has-session` as the source of truth for whether a
# listed child is still alive, not this file. See learnings.md, 2026-08-20.
if [ -n "$HOST_UUID" ]; then
  manifest="/tmp/claude-children-${HOST_UUID}.jsonl"
  python3 -c "
import json, sys
print(json.dumps({'name': sys.argv[1], 'uuid': sys.argv[2], 'cwd': sys.argv[3], 'launched_at': sys.argv[4]}))
" "$NAME" "$sid" "$CWD" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$manifest"
fi

# Two lines: UUID, then a fixed "launched" status -- there's nothing more
# specific to report yet since this script deliberately doesn't wait for the
# turn to finish. Immediately follow this with your OWN backgrounded call to
# watch-child-turn.sh <name> <uuid> -- see rules.md step 2.
echo "$sid"
echo "launched"
