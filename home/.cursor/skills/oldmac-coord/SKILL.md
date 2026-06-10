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
oldmac working <id> "ETA ..."   # "received, working on it" -- does NOT close the item
oldmac presence                 # is each Mac attending the channel now? (ALIVE/STALE)
oldmac storage                  # (oci) mailbox + VM disk-usage report
oldmac thread                   # full conversation
oldmac tasks                    # migration checklist
oldmac sync                     # pull + push now
oldmac listen [sec]             # background listener: [NEW FROM OLD] / [SSH-UP|DOWN] / [OLD ALIVE|STALE]
```
`send` targets: `old | new | both`. Types: `question | task | answer | status | note`.

## Notes
- Append-only + git-synced (GitHub primary, LAN SSH fast path): converges across reboots,
  network changes, and offline periods. A question/task stays in `inbox` until `ack`/`answer`.
- To *listen* for replies, run `oldmac listen` in the background and watch its output for
  `[NEW FROM OLD]` (in Cursor, attach an output watcher on that pattern). `oldmac watch` is the
  human terminal view.
- **Liveness vs delivery (don't conflate):** delivery is guaranteed once a command's git push
  succeeds (a failed push prints a loud WARNING). To know the channel is *attended right now*, use
  `oldmac presence` (ALIVE/STALE per Mac) -- it reads per-role beacons that never touch the message
  log, so checking is free and never spams. `oldmac listen` also flips `[OLD ALIVE]`/`[OLD STALE]`.
  Because the channel is turn-based, the *reply is the ack*; only send `oldmac working <id>` when a
  task will take a while, to tell the asker "in progress" without closing it.
- **Encrypted long-term channel:** the default transport is the migration-era git channel. For a
  permanent, **end-to-end-encrypted** channel brokered by the OCI VM (works off the home LAN too),
  prefix commands with `COORD_TRANSPORT=oci` and run `oci-listen.sh` for real-time receive. Bodies
  are `age`-encrypted with a shared key on both Macs; the VM/GitHub only ever hold ciphertext.
  Design + key/storage/backup/supervision setup: `~/mac-migration/coord/README.md` ("Encrypted OCI channel").
- If `oldmac` isn't on PATH, call `~/mac-migration/coord/coord.sh` directly (same subcommands).
- Full guide: `~/mac-migration/coord/AGENT-GUIDE.md`.
