---
name: oldmac-coord
description: Communicate and coordinate with the user's still-running OLD Mac over a durable, git-synced message channel. Use whenever the user wants to message, ask, task, or check replies from the "old Mac" (or the other/previous Mac), or check migration tasks -- e.g. "ask the old Mac to...", "did the old Mac reply?", "what's left in the migration?". Driven by the agent-neutral `oldmac` CLI, so it works the same in any agent.
disable-model-invocation: false
---

# Coordinate with the old Mac

The user's machine was migrated from an OLD Mac that is still powered on (it hosts the
dealia bot) until it's decommissioned. A durable, git-synced mailbox connects the two Macs.
This is driven entirely by a shell CLI, so it is not Cursor-specific.

## Use the `oldmac` CLI (run from any directory)
```bash
oldmac inbox                    # open messages/tasks from the old Mac
oldmac send old question "..."  # ask the old Mac something
oldmac send old task "..."      # hand it a task
oldmac reply <id> "..."         # answer a message (id from inbox/thread)
oldmac ack <id>                 # mark handled
oldmac thread                   # full conversation
oldmac tasks                    # migration checklist
oldmac sync                     # pull + push now
```
`send` targets: `old | new | both`. Types: `question | task | answer | status | note`.

## Notes
- Append-only + git-synced (GitHub primary, LAN SSH fast path): converges across reboots,
  network changes, and offline periods. A question/task stays in `inbox` until `ack`/`answer`.
- It's turn-based; for a live feed run `oldmac watch` or `~/mac-migration/coord/listen.sh 20`.
- If `oldmac` isn't on PATH, call `~/mac-migration/coord/coord.sh` directly (same subcommands).
- Full guide: `~/mac-migration/coord/AGENT-GUIDE.md`.
