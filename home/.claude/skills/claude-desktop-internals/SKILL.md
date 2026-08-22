---
name: claude-desktop-internals
description: >-
  Reverse-engineered internals of how the Claude Desktop app stores,
  discovers, and displays claude-code sessions on disk (registry vs.
  transcript, hydration, sidebar). Use when you need to synthesize, restore,
  or repair a session's transcript or its position in the app — importing
  chat history from another tool, fixing a mis-titled session, cleaning up
  ghost/orphaned sidebar entries, or debugging why a session isn't showing
  up where expected.
---

# Claude Desktop Internals

Reverse-engineered, undocumented internals of how the Claude Desktop app (the Electron
"Code" tab / `claude-code` CLI it manages) stores, discovers, and displays sessions on
disk. Needed whenever you have to **synthesize, restore, or repair a session's transcript
or its position in the app** — e.g. importing chat history from another tool, fixing a
mis-titled session, or cleaning up ghost sidebar entries.

**Read `~/.claude/skills/claude-desktop-internals/README.md` for the full model** —
architecture diagram (two independent systems: file-scanner search vs. the in-memory
`SessionManager` + on-disk registry, hydrated only at startup), the two files a
synthesized session needs, the validated zero-cost recipe, dead ends, ghost-entry cleanup,
and the "how to re-verify on a new app version" method.

> ⚠️ None of this is documented or supported by Anthropic. It was derived by reading the
> app's own bundled source and controlled experiments, and **will drift across app
> versions** — re-verify before trusting it on a version newer than the one pinned at the
> top of README.md.

## Core mental model (the one thing to internalize before anything else)

A session's `.jsonl` transcript file is visible to **search** the instant it exists on
disk. It is invisible to the **sidebar tree** and the MCP session tools (`list_sessions`,
`get_session`, `set_session_title`) until a separate registry entry exists *and* the app
has hydrated it into memory. Conflating these two systems is the single biggest source of
wrong conclusions when debugging this stuff — see README.md's architecture section for the
full diagram.

This is the foundation `~/.claude/skills/create-new-session-in-claude-desktop/` builds on
for its migrate step.

## Provenance

Migrated 2026-08-21 from `ardiustech/eng_ai_assistant`'s `skills/claude-desktop-internals/`
to this personal, machine-level location (`~/.claude` is symlinked to the `dotfiles` repo,
so this travels to any machine that repo is cloned onto) — pure app-internals knowledge,
not tied to that project. `scripts/` (`cleanup_orphaned_sessions.py`,
`import_cursor_sessions.py`) came along too; they're task-specific tools built on this
model, read README.md before assuming either still matches a newer app version.
