# Create New Session in Claude Desktop — Implementation Guide

How to launch a Claude Code child session that shows up live, correctly named, in Claude
Desktop's sidebar — via the CLI's own remote-control mechanism, not a deep-link import —
and how to convert it into a persistent native Desktop session later, on request.
Redesigned 2026-08-20; the original deep-link-at-launch version of this doc (and its
`bootstrap-session.sh`/`deliver-task.sh` scripts) is superseded. See `learnings.md` for
the investigation that led here and why the old design is gone, not just changed.

This is the "create a brand new session" complement to
`~/.claude/skills/claude-desktop-internals/README.md`, which covers synthesizing/restoring
*existing* transcripts via the raw registry model — this doc's migrate step (step 3
below) still uses that model, but the live/launch phase (steps 1-2) doesn't touch it at
all.

## The core finding: remote-control visibility is automatic and separate from the registry

Confirmed empirically, 2026-08-20, by launching four isolated test panes and checking
Desktop's actual sidebar (screenshot) against `get_session`/`list_sessions` (MCP):

- **Bare `claude` with zero flags** in a tmux pane shows up live in Desktop's sidebar,
  under a default name (confirmed by the user: "computer name + random words," the same
  scheme untitled sessions use).
- **`-n <name>` alone** (no `--remote-control`) shows up with that exact name.
- **`--remote-control <name>` alone** (no `-n`) shows up with that exact name too, and
  additionally prints a `claude.ai/code/session_...` URL (phone/web control).
- **All four test sessions returned `Session ... not found`** from `get_session`, and
  none appeared in `list_sessions` — confirmed this is a genuinely different code path
  from the deep-link "recover CLI session" import the old design relied on. The registry
  files under `claude-code-sessions/*/*/local_<uuid>.json` are never written by this path
  at all until something explicitly imports the transcript (the migrate step).
- The user separately confirmed (from direct experience, not tested live in this session):
  killing the tmux pane (or the underlying process) makes the sidebar entry disappear
  immediately — it's a live reflection of a running process, not a persisted record.

**Practical conclusion:** use both `-n <name>` and `--remote-control <name>` (same value)
when launching — `-n` for the prompt-box/terminal-title/resume-picker label, `--remote-control`
for the same sidebar label plus the phone/web control link. Neither is required for bare
sidebar visibility, but both are worth setting since they're free and give a real name
instead of the hostname+random-words default.

## Why tmux, why not `-p`

Same reasoning as before: `claude -p "prompt"` (headless one-shot) produces a session with
a generic placeholder title and a stray re-attaching process — see
`claude-desktop-internals`'s "Dead ends" section. A plain interactive `claude` REPL in a
detached tmux pane, driven by `tmux send-keys`, is indistinguishable from a human typing —
the normal interactive code path, and the one the remote-control mechanism above expects.

## Why one CLI turn now, not two — but still two tool calls

The prior design split a fast "prove you're alive" seed turn from the real task, because
registering via the deep link and setting the title both needed to happen before the real
task's own (possibly slow) turn completed — otherwise the sidebar entry, title, and
permission-mode patch all showed up late. That constraint is gone: remote-control
visibility and naming happen automatically at process launch, with no import step to gate
anything behind. So the real task is now sent as the very first turn, prefixed with a
short note identifying the parent session (see rules.md, "Parent context").

There are still two tool calls on the orchestrating side — `launch-child-session.sh` then
`watch-child-turn.sh` — but for a different reason than the old seed/real-task split: the
first confirms the child exists and returns its UUID fast; the second is what makes a
completion notification actually reach the parent's chat, since it's the one running as a
backgrounded call the harness can report back on (see step 2 below).

## The mechanism, step by step

### 1. Launch (`launch-child-session.sh`)

```bash
~/.claude/skills/create-new-session-in-claude-desktop/launch-child-session.sh --same-project <name> "<task prompt>"
```

What it does, in order:
1. Resolves `<cwd>` (the `--same-project` sentinel, or an explicit path — same
   cwd-resolution logic and rationale as the old `bootstrap-session.sh`: read the calling
   session's own registry `cwd` via `CLAUDE_CODE_HOST_SESSION_ID`, never `$PWD`).
2. Reads the calling session's `model`/`effort`/`permissionMode` and builds
   `-n <name> --remote-control <name> --model ... --effort ... --permission-mode ...`.
   This inheritance is still necessary even though nothing gets persisted to a registry
   entry anymore — it's what lets a tool-approval mid-task not hang forever when
   `send-keys` has no human to click "yes" for.
3. Registers a `Stop` hook (via `--settings`, scoped to this process, sentinel path keyed
   by `<name>`) — same mechanism as before, confirmed still fires correctly under
   `-n`/`--remote-control` (2s turnaround in a live test, 2026-08-20). See the original
   "Turn-completion detection" investigation below for why a Stop hook and not
   pane-render inference.
4. `tmux new-session -d -s <name> -c <cwd> "claude <args>"`.
5. Waits for the REPL's idle prompt (dismissing the one-time "trust this folder" dialog if
   this `cwd` is new). **Gotcha:** the prompt line ends in a non-breaking space
   (`U+00A0`), not ASCII — match `^❯`, never `^❯ *$`.
6. Snapshots `*.jsonl` filenames under the target cwd's project dir *before* launch, sends
   the real task (prefixed with parent-session context) as the first turn, then polls
   (1s intervals, ~20s budget) for a new filename to appear — not `ls -t | head -1`, which
   misidentifies the session whenever another live session shares the same cwd and writes
   concurrently (confirmed incident, see the 2026-08-17 entries in `learnings.md`).
7. **Returns immediately once the transcript is found — does NOT wait for the task
   itself to finish.** Confirmed empirically (2026-08-21): the transcript `.jsonl` file
   exists within ~1s of sending a turn (the session-init/`bridge-session` lines land
   before the assistant even starts replying), so there's nothing to gain by blocking here
   — a live end-to-end timing test measured the whole script at **3.4 seconds** wall clock
   for a real launch, versus the old design's up-to-10-minute blocking wait.
8. Appends `{name, uuid, cwd, launched_at}` to `/tmp/claude-children-<parent-uuid>.jsonl`
   — a dumb, append-only log for later bulk migration. Not a liveness signal; always check
   `tmux has-session` before acting on an entry.
9. Prints the transcript UUID, then the fixed word `launched`.

**Does NOT open the deep link, does NOT set a title, does NOT wait for the task, does NOT
kill the pane on completion, and has NO watchdog.** All of these were deliberate features
of the old design that no longer fit: the deep link/title are deferred to the migrate
step; waiting for the task blocks the parent's own turn for no reason (see step 2 below
for what replaced it); killing the pane on completion would defeat the whole point of
being able to send more turns; a 1-hour watchdog would kill sessions the user might want
to keep around for days.

### 2. Get notified when the first round finishes (`watch-child-turn.sh`)

```bash
~/.claude/skills/create-new-session-in-claude-desktop/watch-child-turn.sh <name> <uuid>
```

**Must be invoked by the calling agent as its own backgrounded tool call** (e.g. the Bash
tool with `run_in_background: true`) immediately after step 1 returns. This is the actual
mechanism behind "background task that polls and notifies the parent" — the harness
delivers a task-completion notification into the parent's conversation when a backgrounded
call exits; a bare shell-level background process (`... & disown`) has no equivalent
channel, so building the polling loop *inside* `launch-child-session.sh` and disowning it
would never actually notify anyone. Verified end-to-end, 2026-08-21: launched a real child,
backgrounded this script via the Bash tool, and when the child's turn completed the harness
delivered a `<task-notification>` whose output was exactly the one-line message below —
confirming the whole chain (Stop hook → sentinel file → poll loop → backgrounded-tool-exit
→ harness notification → agent relays to user) works as designed.

What it does: polls `/tmp/claude-child-stopmark-<name>` (the same sentinel
`launch-child-session.sh`/`send-turn.sh` use) every 3 seconds. On the *same* loop —
not gated behind the sentinel — it also greps the transcript for a bare `Login expired`
turn, since a login-expired session never fires the Stop hook at all (see the 2026-08-13
entry in `learnings.md`); without this independent check a dead session would poll
silently for the full budget below before anyone found out. Terminal outcomes:
- **Sentinel fires:** prints `Child session '<name>' (uuid <uuid>) finished its current
  turn. Ask the user if they want to migrate it to Desktop: ...` and exits 0.
- **Login-expired detected** (via the sentinel path or the independent grep, whichever
  happens first): prints a distinct message telling the human to `tmux attach` and
  `/login` by hand, exits 0.
- **The tmux pane disappears without the sentinel ever firing** (most likely: someone ran
  `migrate-to-desktop.sh` or closed the pane by hand while this was polling): prints that
  there's nothing further to notify and exits 1.
- **4-hour timeout**: prints a "still running, not necessarily a problem" message and
  exits 0 rather than polling forever.

Same sentinel convention works for any `send-turn.sh` call too, not just the first —
background this script after a follow-up turn instead of letting `send-turn.sh` block if a
10-minute synchronous wait doesn't fit.

### 3. Keep talking to it (`send-turn.sh`)

```bash
~/.claude/skills/create-new-session-in-claude-desktop/send-turn.sh <name> "<prompt>"
```

Sends another turn into the same still-open pane, reusing the sentinel-per-name
convention (`rm -f`s any stale sentinel first — the same guard the old `deliver-task.sh`
needed, for the same reason: a leftover sentinel from a prior turn would make the wait
loop return instantly and report "done" before the new turn even ran). Repeatable
indefinitely; never tears the pane down itself. Still blocks synchronously up to 10
minutes by default — pair with `watch-child-turn.sh` (backgrounded) instead if that's too
long to wait on.

### 4. Migrate to a real Desktop session (`migrate-to-desktop.sh` + `set_session_title`)

```bash
~/.claude/skills/create-new-session-in-claude-desktop/migrate-to-desktop.sh <name> <uuid>
```

1. If the tmux pane is still alive: sends `/exit`, polls `tmux has-session` until it's
   gone (falls back to a hard `tmux kill-session` after ~15s if `/exit` doesn't land). The
   deep-link import path recovers an *orphaned* CLI transcript — firing it while the
   process still holds the session live has never been tested and isn't assumed safe.
   If the pane is already gone (closed by hand, reboot, etc.), it says so and proceeds —
   the transcript is already orphaned either way.
2. `open "claude://resume?session=<uuid>"` — same deep-link mechanism documented in the
   original version of this doc: Desktop's own URL-scheme handler imports the CLI
   transcript by id and creates a registry entry immediately, live, no quit+relaunch
   required. (See `claude-desktop-internals` for why this supersedes that doc's "registry
   is read ONLY at app startup" claim for this specific import path.)
3. **From the orchestrating agent** (not the script — this needs the `ccd_session_mgmt`
   MCP tool, only available in a Desktop-hosted session): call
   `set_session_title(session_id="local_<uuid>", title="<name>")`. Do this every single
   time — confirmed directly by the user's own testing that BOTH this deep-link path AND
   the CLI's `/desktop` command wipe or generic-title the session on conversion. There is
   no known-good conversion path that preserves the title automatically.
4. Tell the user the migrated session sits at `permissionMode: default` (Manual) until
   they click its permission-mode chip in Desktop's UI — a live, instant, no-restart fix
   (see `learnings.md`, 2026-08-14). This skill does not patch permission mode on disk;
   that's an unrelated, deliberate decision from 2026-08-20, independent of this whole
   remote-control redesign.

**Bulk migration** ("close off child sessions"): read
`/tmp/claude-children-<parent-uuid>.jsonl`, and for each `{name, uuid}` line, check
`tmux has-session -t <name>` to see whether it's worth tearing down vs. already gone, then
run the three steps above for each. The manifest only tells you *what was launched*, never
*what's still alive* — that's always a live `tmux has-session` check.

**Optional: `fix-session-timestamps.py <uuid>`** — corrects the migrated session's
`createdAt`/`lastActivityAt` (stamped to "now" on import) to the transcript's real
first/last message timestamps. Worth noting this is *more* valuable to run now than in
the old design, not equally so: these sessions often run live for hours before a migrate
request, so the "now" stamp drifts further from reality than a session that used to get
imported within seconds of being created. Still cosmetic-only (sidebar sort order), still
needs a Desktop quit+relaunch to actually show up, still optional — see its own docstring
for `--from`/`--dry-run`/`--no-settings` usage.

## Turn-completion detection: a Stop hook, not pane-render inference (carried over, unchanged)

Confirmed live (2026-08-11) that watching the tmux pane for "content stopped changing" is
not viable — the CLI's own terminal repaint can go stale for 20+ *consecutive* 2-second
polls while genuinely still thinking, so no finite stability window is safe. Matching
busy-indicator text (`"esc to interrupt"`, `"Thinking"`, etc.) is worse — it breaks
whenever the CLI's spinner vocabulary changes. The transcript `.jsonl` file isn't a
substitute either — confirmed flat for 40+ seconds during active visible streaming. The
fix, unchanged from the original design: register a `Stop` hook (via `--settings`) that
touches a sentinel file; poll for that file's existence. Fires exactly once,
deterministically, at true turn completion — verified again in this redesign under
`-n`/`--remote-control` specifically (2s turnaround for a trivial reply).

## Cleanup / lifecycle

**Between launch and either a `send-turn.sh` call or a migrate, indefinitely, on
purpose.** No watchdog. The pane stays alive exactly as long as the user wants to keep
talking to that child — this is the central behavior change from the old design, which
capped an unattended pane at one hour. If a child is abandoned and never migrated or
closed, it just keeps running until the human kills it by hand or restarts their machine.

**After `migrate-to-desktop.sh`, no live process remains** — same as the old
`deliver-task.sh`'s teardown: `/exit` + `tmux kill-session` leaves a normal closed,
resumable Claude Code session on disk, indistinguishable from any other. Desktop resumes
it the same way it resumes any previously-closed session.

## Related prior art

The user's own Raycast extension
(`~/workspace/personal/raycast_scripts/claude-session-search`) reopens *existing*
registered sessions via the same `claude://resume?session=` deep link this skill's migrate
step uses — see its `src/search-sessions.tsx` → `openInClaudeDesktop()`. It has no
equivalent to the launch/remote-control phase this skill adds, since it only ever
operates on sessions that already have a transcript.
