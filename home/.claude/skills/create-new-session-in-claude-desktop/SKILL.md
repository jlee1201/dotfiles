---
name: create-new-session-in-claude-desktop
description: >-
  Launch a Claude Code child session that shows up live and correctly named in
  Claude Desktop's sidebar via remote-control (no import, no restart), keep
  driving it from the parent, and optionally migrate it to a persistent native
  session later. Use when asked to start a session that shows up in the
  sidebar, create a new Claude Desktop session with a prompt, spin up a
  session to pick up later, or bootstrap a titled session.
---

# Create New Session in Claude Desktop

Launch a Claude Code child session that's **immediately visible, correctly named, in
Claude Desktop's sidebar** — no deep-link import, no registry patch, no restart — by
running it inside tmux with the CLI's own `-n`/`--remote-control` flags. The pane (and the
sidebar entry) live for as long as you want; only convert it into a persistent native
Desktop session when explicitly asked to.

**Read `~/.claude/skills/create-new-session-in-claude-desktop/README.md` for the full
mechanism, evidence, and script usage.** Read
`~/.claude/skills/claude-desktop-internals/README.md` first if you haven't — this skill
still relies on that doc's registry/transcript model for the migrate step.

## Trigger

"Start a session that shows up in my sidebar", "create a new Claude Desktop session with
this prompt", "spin up a session for X I can pick up later", "bootstrap a titled session",
or anything asking to launch new agent work such that it's visible/resumable from the
Claude Desktop left nav rather than just a terminal or a background task.

## Why this design — confirmed 2026-08-20, supersedes the old deep-link-at-launch recipe

A prior version of this skill registered every child via `claude://resume` at launch time,
which meant paying that path's known bugs (title mangled, `permissionMode` hardcoded to
Default) immediately, for every session, whether or not it ever needed to outlive the
launch process. Investigation (see `learnings.md`, 2026-08-20) found a cheaper mechanism:
**any interactive `claude` process in a tmux pane already shows up live in Desktop's
sidebar** via the CLI's remote-control channel — no deep link, no registry write. `-n
<name>` and `--remote-control <name>` each independently set the display name shown.
This is a genuinely different, lighter-weight visibility path than the deep-link import:
it's ephemeral (the sidebar entry disappears the instant the process dies — confirmed by
the user directly) and ISN'T queryable via `get_session`/`list_sessions` (those read the
persisted registry, which this path never writes to).

So the new design defers the deep-link's known bugs until the moment you actually want a
session to survive past the tmux pane's lifetime — not on every launch.

## The recipe

1. **Launch the child.** Run
   `~/.claude/skills/create-new-session-in-claude-desktop/launch-child-session.sh <cwd>|--same-project <name> "<task prompt>"`.
   This starts `claude -n <name> --remote-control <name> [inherited flags] --settings
   <stop-hook-json>` in a detached tmux pane named `<name>`, waits for the REPL to be
   ready (dismissing the one-time "trust this folder" prompt if needed), prefixes the real
   task with a short note identifying the parent session (see "Parent context" below),
   sends it, and **returns fast** — a few seconds, just long enough to confirm the child is
   alive and locate its transcript UUID. It does NOT wait for the task itself to finish.
   Prints the UUID, then the fixed word `launched`.
   - Run this call in the foreground (it's fast now — no need to background it itself).
   - **Always pass `--same-project` as `<cwd>`** unless the user explicitly names a
     different target project or worktree — see the cwd-resolution guidance carried over
     from the old recipe in `learnings.md` (1361-session audit; Desktop never remaps
     `cwd`, so a session landing under the wrong project always traces back to the wrong
     argument here, not a Desktop bug). For a worktree of a submodule inside the calling
     project (not a different top-level project), still pass `--same-project` and set
     `CHILD_EXTRA_DIR=<worktree path>` instead — grants `--add-dir` access without
     touching the session's own cwd. For a genuinely different top-level project, pass
     that project's path directly; the script auto-adds `--add-dir <calling project>` so
     the child still sees the calling project's CLAUDE.md/skills too (`CHILD_NO_ADD_DIR=1`
     to suppress).
   - `<name>` becomes the tmux session name, the `-n` display name, and the
     `--remote-control` name — all identical on purpose. Pick something short and
     meaningful; you'll reuse it for every later interaction with this child.
   - Keep both the printed UUID and `<name>` — both are needed for every later step.
   - The script records `{name, uuid, cwd, launched_at}` as one line in
     `/tmp/claude-children-<parent-uuid>.jsonl` — a dumb append-only manifest for later
     bulk discovery (see "Migrating" below). It is NOT a status oracle; always verify a
     listed child's liveness with `tmux has-session`, never trust the manifest alone.

2. **Immediately kick off the watcher as your own backgrounded call.** Run
   `~/.claude/skills/create-new-session-in-claude-desktop/watch-child-turn.sh <name> <uuid>`
   with `run_in_background: true` (e.g. on the Bash tool call) right after step 1 returns. This
   is the actual mechanism behind "notify me when the child's first round finishes" — the
   harness delivers a task-notification when a backgrounded call exits, which is the only
   way to get a message into the parent chat asynchronously. A plain shell-level background
   process (`... & disown`) has no such channel; don't try to build one inside
   `launch-child-session.sh` itself. It polls the same Stop-hook sentinel the launch script
   registered, checking independently on every poll for a bare `Login expired` transcript
   turn (which never fires the Stop hook at all — see learnings.md, 2026-08-13). When it
   exits, relay its one-line message to the user verbatim-ish and explicitly ask if they
   want to migrate. It also fires this way for any subsequent `send-turn.sh` call if you
   want an async notification for a long-running follow-up turn instead of blocking on it —
   same sentinel convention, not just for round 1.

3. **Keep interacting with the child via the parent (default).** As long as the user
   hasn't asked to close it off, the tmux pane and `claude` process stay alive indefinitely
   — no watchdog kills it. To send another turn (the user asking a follow-up, or the child
   itself reporting it needs more context — see below), run
   `~/.claude/skills/create-new-session-in-claude-desktop/send-turn.sh <name> "<prompt>"`. Repeatable;
   it never tears the pane down. It waits up to 10 minutes for that turn's Stop-hook
   sentinel and reports done/still-warning the same way (or background it with
   `watch-child-turn.sh` too, per step 2, if a 10-minute blocking wait doesn't fit).

4. **Migrate to a real Desktop session — only when asked.** Trigger phrases like "close
   off child sessions", "migrate sessions to claude desktop", or similar. For each child
   the user means (a specific `<name>`, or all of them — read
   `/tmp/claude-children-<parent-uuid>.jsonl` and check `tmux has-session` per entry to see
   which are actually still around):
   1. Run `~/.claude/skills/create-new-session-in-claude-desktop/migrate-to-desktop.sh <name> <uuid>`.
      It gracefully `/exit`s the pane (falling back to a hard `tmux kill-session` if that
      doesn't land), confirms the pane is actually gone (the deep link recovers an
      *orphaned* transcript — firing it while the process still holds the session is
      untested), then opens `claude://resume?session=<uuid>`.
   2. Call `set_session_title(session_id="local_<uuid>", title="<name>")` (the
      `ccd_session_mgmt` MCP tool — Desktop-hosted sessions only). **Do this every time** —
      confirmed by the user's own testing that both this deep-link path and the CLI's
      `/desktop` command wipe/generic-title the session on conversion.
   3. Tell the user: the migrated session's permission mode defaults to Manual until they
      click its permission-mode chip in Desktop's UI once it appears in the sidebar — a
      live, instant fix, no restart (see learnings.md, 2026-08-14). This skill does not
      patch permission mode on disk; that was a deliberate decision (learnings.md,
      2026-08-20), independent of this whole remote-control redesign.
   - Optional, not part of the default flow: `fix-session-timestamps.py <uuid>` corrects
     the migrated session's `createdAt`/`lastActivityAt` (stamped to "now" on import,
     which is now a *bigger* drift than before — these sessions often have real activity
     spread over hours before migration, not minutes) if sidebar chronological order
     matters to the user. Cosmetic-only; still needs an eventual Desktop restart to show
     up. Batch it rather than restarting per session.

## Parent context (child querying back)

The task prompt `launch-child-session.sh` sends is always prefixed with the parent
session's title, session UUID, and cwd (enough to locate the parent's own transcript file
on disk directly: `~/.claude/projects/<encoded-parent-cwd>/<parent-uuid>.jsonl`). This is
deliberately NOT wired to any live cross-session mechanism (no agentbus, no MCP channel) —
per user preference, 2026-08-20, it's just enough identifying info that a later round of
the child (or a human) can go read the parent's transcript directly, or the child can state
plainly in its response what context it's missing so the human can relay it via
`send-turn.sh`. Don't build more than this without being asked.

## Don't

- Don't use `claude -p "..."` (headless one-shot) — confirmed dead end in
  `claude-desktop-internals`: generic placeholder titles, stray re-attaching processes.
- Don't open the `claude://resume` deep link at launch time — that's the old design. It
  immediately pays the title/permission-mode-mangling cost this recipe defers until an
  explicit migrate request, for no benefit (the child is already visible live via
  remote-control).
- Don't treat a timeout warning from `send-turn.sh`, or `watch-child-turn.sh`'s "still
  running after 4 hours" message, as a failure — a child outliving the wait budget is
  normal now. Only a login-expired message is a real failure worth surfacing immediately.
- Don't have `launch-child-session.sh` wait for the task to finish — it deliberately
  returns in seconds. If a future edit is tempted to "simplify" by merging the wait back
  in, it defeats the entire point of step 2 (`watch-child-turn.sh` as its own backgrounded
  call) and blocks the parent's turn for however long the child's task takes.
- Don't kill a child's tmux pane just because its task finished — the pane staying alive is
  the point (so the parent can keep sending turns). Only tear it down via
  `migrate-to-desktop.sh`, or when the user says to close it, or the human does it by hand.
- Don't trust `/tmp/claude-children-<uuid>.jsonl` as a liveness signal — it's an
  append-only launch log, not a status store. Always check `tmux has-session` per entry
  before acting on it.
- Don't wire the parent-context prefix up to agentbus or any other live query channel
  without being asked — see "Parent context" above.
- Don't skip `set_session_title` after a migrate — both known conversion paths wipe the
  title every time, confirmed by direct testing, not an occasional glitch.
- Don't patch permission mode on disk as a "helpful" fix at migrate time — that was a
  deliberate, separate decision (learnings.md, 2026-08-20): tell the user to click the
  chip in Desktop's UI instead.

## Provenance

Migrated 2026-08-21 from `ardiustech/eng_ai_assistant`'s `skills/create-new-session-in-claude-desktop/`
to this personal, machine-level location (`~/.claude` is symlinked to the `dotfiles` repo,
so this travels to any machine that repo is cloned onto) — the skill is entirely about
Claude Desktop app internals, not about that specific project, so it doesn't belong forked
per-workspace. The eng_ai_assistant copy now just points here.
