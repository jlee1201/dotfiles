---
name: oldmac-coord
description: Communicate and coordinate with the user's still-running OLD Mac over a durable, git-synced message channel. Use whenever the user wants to message, ask, task, or check replies from the "old Mac" (or the other/previous Mac), or check migration tasks -- e.g. "ask the old Mac to...", "did the old Mac reply?", "what's left in the migration?". Driven by the agent-neutral `oldmac` CLI, so it works the same in any agent.
disable-model-invocation: false
---

# Coordinate with the old Mac

The user's machine was migrated from an OLD Mac that **stays powered on as Dealia's permanent
home server** (it hosts the dealia bot + the always-on services). A durable mailbox connects the
two Macs over an **end-to-end-encrypted channel brokered by the OCI VM** (near-real-time; the git
channel is now only the hourly ciphertext backup). Driven entirely by a shell CLI, so it's not Cursor-specific.

## Use the `oldmac` CLI (run from any directory)
```bash
oldmac inbox                    # open messages/tasks from the old Mac
oldmac send old question "..."  # ask the old Mac something
oldmac send old task "..."      # hand it a task
oldmac reply <id> "..."         # answer a message (id from inbox/thread)
oldmac ack <id>                 # mark handled
oldmac working <id> "ETA ..."   # "received, working on it" -- does NOT close the item
oldmac presence-oci             # LIVENESS CHECK — use THIS (or a live round-trip): is the old Mac's encrypted listener attached to the VM right now?
oldmac presence                 # git/LAN beacon ONLY — lags; routinely reads STALE even when the old Mac is live on OCI. Do NOT use it to conclude the old Mac is idle/offline.
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
- **Liveness vs delivery (don't conflate):** delivery is guaranteed once a send succeeds (a failed
  push prints a loud WARNING). **Caveat under the OCI default:** `oldmac presence` (ALIVE/STALE) and
  `oldmac listen` (`[SSH-UP|DOWN]`, `[OLD ALIVE|STALE]`) are **git-channel / LAN** signals -- an OCI
  send refreshes only the sender's *local* beacon and does NOT git-push it, so `presence` can read
  STALE and `listen` `[SSH-DOWN]` even while the old Mac is actively on OCI (this exact gotcha caused
  a false "offline 11h" read on 2026-06-10). To judge **OCI** liveness, look at recent `oldmac inbox`
  activity (message timestamps off the VM mailbox), run `oci-listen.sh`, or do a live round-trip.
  Because the channel is turn-based, the *reply is the ack*; only send `oldmac working <id>` when a
  task will take a while, to tell the asker "in progress" without closing it.
- **Encrypted OCI channel is the default (cutover completed 2026-06-09).** Commands use the
  **end-to-end-encrypted** channel brokered by the OCI VM (works off the home LAN too) with **no
  prefix needed**; bodies are `age`-encrypted with a shared key on both Macs, so the VM/GitHub only
  ever hold ciphertext. For real-time receive, run `oci-listen.sh`. The legacy plaintext git channel
  is retained as the hourly ciphertext backup and the presence transport; force it per command with
  `COORD_TRANSPORT=git`. Design + key/storage/backup/supervision setup:
  `~/mac-migration/coord/README.md` ("Encrypted OCI channel").
- If `oldmac` isn't on PATH, call `~/mac-migration/coord/coord.sh` directly (same subcommands).
- **Need a remote *shell* on the old Mac (not just messaging)?** Normally just delegate via
  `oldmac send old task "..."` (the old Mac agent has local shell). To drive it yourself, or run a
  privileged command without exposing a secret to either agent, use `tools/home-lan/connect.sh`
  (dealia repo) over the old Mac's permanent reverse-SSH tunnel. The old Mac is Gusto-managed:
  **no passwordless sudo**, and remote **GUI/Screen Sharing is MDM-blocked** (no VNC). Details:
  dealia `context/constraints/infrastructure-topology.md`.
- Full guide: `~/mac-migration/coord/AGENT-GUIDE.md`.
