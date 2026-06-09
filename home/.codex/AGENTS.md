# Global agent instructions

## Coordinating with the old Mac (`oldmac`)
This machine was migrated from an older Mac that is **still running** (it hosts the dealia
bot) until it's decommissioned. A durable, git-synced message channel connects the two.

Any time the user wants to talk to / coordinate with the **old Mac**, use the `oldmac` CLI
from any directory (no need to be in a particular repo):

- `oldmac guide` -- full usage (read this first if unsure)
- `oldmac inbox` -- messages/tasks waiting from the old Mac
- `oldmac send old question "..."` / `oldmac send old task "..."` -- ask it something / hand it work
- `oldmac reply <id> "..."`, `oldmac ack <id>`, `oldmac thread`, `oldmac tasks`

It's append-only and git-synced (survives reboots/offline). Engine + full guide:
`~/mac-migration/coord/AGENT-GUIDE.md`. If `oldmac` isn't on PATH, call
`~/mac-migration/coord/coord.sh` directly (same subcommands).
