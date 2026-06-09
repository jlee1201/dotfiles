- allow referencing hidden files prefixed with a "." including directories that are prefixed with "." like ".buildkite"
- don't add the claude co-authorship to git commit messages unless explicitly asked for
- when I explicitly ask in prompt to run a git command (ie: commit, push), do not prompt me again to ask if I allow to run command -- auto allow this
- gh cli should be an allowed tool to be used to interact with pull requests

## Coordinating with the old Mac (`oldmac`)
- This machine was migrated from an OLD Mac that is still running (hosts the dealia bot) until it's decommissioned. A durable git-synced channel connects them.
- To message/coordinate with the old Mac from any directory, use the `oldmac` CLI: `oldmac guide` (usage), `oldmac inbox` (read its messages), `oldmac send old question "..."` / `oldmac send old task "..."`, `oldmac reply <id> "..."`, `oldmac tasks`.
- Append-only + git-synced (works offline, syncs later). Full guide: `~/mac-migration/coord/AGENT-GUIDE.md`. If `oldmac` isn't on PATH, call `~/mac-migration/coord/coord.sh` directly.