- allow referencing hidden files prefixed with a "." including directories that are prefixed with "." like ".buildkite"
- don't add the claude co-authorship to git commit messages unless explicitly asked for
- when I explicitly ask in prompt to run a git command (ie: commit, push), do not prompt me again to ask if I allow to run command -- auto allow this
- gh cli should be an allowed tool to be used to interact with pull requests

## Bias to action (applies to all projects)
- Default to acting on clear requests. Just do the task instead of asking about it.
- Only ask clarifying questions when the request is genuinely ambiguous, the action is irreversible/destructive, or you're actually blocked and cannot proceed sensibly with defaults.
- Do NOT run the brainstorming skill (or any interview/requirements-gathering flow) unless I explicitly ask to brainstorm, plan, or design.
- These instructions take precedence over any plugin/skill guidance (e.g. superpowers) that pushes toward front-loading clarifying questions.

## Multi-machine / multi-agent coordination (Matrix agent-bus)
- There's an always-on OLD Mac that hosts the dealia bot. **Decommissioning it is NOT decided** — it may stay indefinitely as an always-on machine; don't assume it's going away.
- Cross-machine and cross-session agent coordination runs on the **Matrix agent-bus** — rooms-as-lanes on the family Continuwuity server (E2EE; each lane is a room, isolated by membership). Use the `agentbus` CLI from any directory: `agentbus onboard` (once per machine), `agentbus lanes`, `agentbus send <lane> "..."`, `agentbus watch <lane>`, `agentbus react <lane> <event> <emoji>`.
- Design + deployment record: `~/workspace/personal/dealia/docs/superpowers/specs/2026-07-02-matrix-rooms-as-lanes-agent-bus-design.md`. Tool: `~/workspace/personal/dealia/tools/matrix/agentbus/`.