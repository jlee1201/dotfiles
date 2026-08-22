# Create New Session in Claude Desktop — Learnings

## Split launch from wait-for-completion so the parent can be notified asynchronously — 2026-08-21

User-driven follow-up to the 2026-08-20 remote-control redesign: "after the parent session
launches the child task, it should create a background task that polls mechanically to see
when the child task finishes... notify in the parent task that the first round finished and
remind/ask the user if they want to migrate."

**The version of `launch-child-session.sh` from earlier the same day still blocked
synchronously** on the Stop-hook sentinel (up to 10 minutes) before returning — a leftover
from the old design's wait loop that nothing had actually removed yet, it had just lost its
login-expired-detection urgency once the deep-link-at-launch registration went away. This
meant the parent's own turn sat blocked for however long the child's first round took,
which is exactly what the two-phase split in the 2026-08-18 entry (below) was originally
built to avoid — reintroduced here for a different reason.

**Key empirical finding that made the fix possible:** tested whether the transcript
`.jsonl` file appears at turn-*start* or only at turn-*completion* (this was previously
untested — the old design always diffed transcripts only after a completed seed/real
turn). Launched a real tmux pane, sent a "think for a while" prompt, and checked the
project dir every second: **the file existed within ~1 second**, containing the
`bridge-session`/session-init lines, well before the assistant even began its reply. This
means UUID detection never needed to wait for task completion at all — it only ever needed
to wait for the *turn to start*, a assumption inherited from the old design without ever
being questioned until now.

**Fix:** removed the sentinel-wait loop from `launch-child-session.sh` entirely — it now
only polls (1s, ~20s budget) for the new transcript filename to appear, then returns
immediately. New script `watch-child-turn.sh <name> <uuid>` owns the actual "wait for the
sentinel" responsibility, with a generous 4-hour budget and the same independent
login-expired grep the old wait loop had (necessary because a login-expired session never
fires the Stop hook at all — see the 2026-08-13 entry below — so gating that check behind
the sentinel would miss it).

**The most non-obvious point, worth restating for a future edit:** `watch-child-turn.sh`'s
own polling loop is not what delivers the notification — a plain shell background process
(`... & disown`, the same pattern used for the old 1-hour orphan watchdog) has no channel
into the Claude Code chat at all. The notification only happens because the *orchestrating
agent* invokes `watch-child-turn.sh` as its own tool call with `run_in_background: true`
(Claude Code's Bash tool) — the harness is what delivers a `<task-notification>` back into
the conversation when a backgrounded call exits. Don't try to move the polling back inside
`launch-child-session.sh` with a disowned background process "to simplify" — it would
silently break the entire notify mechanism while still looking like it works (the script
would exit fine, the OS-level loop would run fine, nothing would ever tell the parent).

**Verified end-to-end, live, same session:** launched a real child (`launch-child-session.sh`
returned in 3.4s per `time`), backgrounded `watch-child-turn.sh` via the Bash tool, and
received a genuine `<task-notification>` when the child's turn completed — output was
exactly the intended one-line message ("Child session '...' finished its current turn.
Ask the user if they want to migrate it to Desktop: ..."). This confirms the full chain:
Stop hook → sentinel file → `watch-child-turn.sh` poll loop → backgrounded-tool-call exit
→ harness notification → agent relays to user. Not simulated or assumed — the notification
in this session's own transcript is the proof.

## Redesign: remote-control live visibility replaces deep-link-at-launch — 2026-08-20

User-driven investigation (not this agent's finding first): starting a Claude CLI session
with remote control on shows up in Claude Desktop directly, `-n` names it properly, and
killing the tmux pane/process makes it disappear. Converting it to a persistent session
(via `/desktop` or the deep link) obliterates the title and doesn't carry permissions —
same known bug in both conversion paths, confirmed by the user's own testing of both.

**Empirically verified before rewriting anything** (four isolated tmux panes, checked
against both a live Desktop screenshot and `get_session`/`list_sessions`):
- Bare `claude` (zero flags) already shows up live in Desktop's sidebar, under a default
  "computer name + random words" name (the user's words, confirmed by screenshot — showed
  up as `john-lee-lh00t246xr-curried-newell`-style under a group named "Other").
- `-n <name>` alone → shows up named `<name>`.
- `--remote-control <name>` alone → shows up named `<name>` too, plus prints a
  `claude.ai/code/session_...` URL (phone/web control link).
- **None of the four appeared in `get_session`/`list_sessions`** — confirmed this
  mechanism is entirely separate from, and never writes to, the persisted registry
  (`claude-code-sessions/*/*/local_<uuid>.json`) that the old bootstrap+deep-link design
  and `claude-desktop-internals` are both built around. The "Other" grouping in the
  screenshot is a **live, ephemeral, remote-control-sourced sidebar view**, not the same
  thing as a registered session showing up under a fallback project group — don't
  conflate the two even though visually they may render in the same sidebar list.
- Confirmed a Stop-hook sentinel (the turn-completion mechanism this skill has always
  used) still fires correctly when combined with `-n`/`--settings` (2s turnaround for a
  trivial reply) — the redesign didn't need a fifth turn-completion mechanism.

**Decision, informed by two explicit user answers:**
1. Keep `--remote-control` even though it's not required for bare sidebar visibility —
   user wants the phone/web control link too. Pass the same `<name>` to both `-n` and
   `--remote-control` so every label matches.
2. Don't wire the parent→child query-back mechanism to agentbus or any other live
   channel. Just prefix the child's first turn with the parent's title/UUID/cwd (enough
   to `Read`/`grep` the parent's own transcript file directly if a later round needs
   context it wasn't given) and otherwise treat it as human-relay: the child states what's
   missing, the human sends it via `send-turn.sh`. Explicitly out of scope for this skill
   to build more than that.

**What this replaces, concretely:** the old two-phase `bootstrap-session.sh` (fast seed
turn + immediate `claude://resume` registration) + `deliver-task.sh` (send real task,
`/exit`, teardown) is gone, replaced by `launch-child-session.sh` (one turn, the real
task, sent immediately — no seed turn needed since naming/visibility no longer gate on an
import step) + `send-turn.sh` (repeatable, doesn't teardown) + `migrate-to-desktop.sh`
(teardown + deep link only; title-setting is a separate MCP call the orchestrating agent
makes, same as before). The 1-hour watchdog is gone entirely — a child living for days
until explicitly migrated or closed is the intended behavior now, not a leak to guard
against.

**Design consequences worth restating so a future edit doesn't quietly regress them:**
- A child's tmux pane finishing its task is not a signal to tear anything down — that's
  the opposite of the old design, where task completion triggered `/exit`. Only an
  explicit migrate/close request, or the human doing it by hand, ends a child's live pane.
- The deep-link's title/permission-mode-mangling bug (documented extensively in this
  file's older entries below) still exists and is NOT fixed by this redesign — it's just
  deferred from "every launch" to "only at migrate time," which is strictly fewer times it
  gets paid, not zero.
- The manifest (`/tmp/claude-children-<parent-uuid>.jsonl`) exists solely so a "close off
  child sessions" request has something to enumerate. Keep it dumb: one append-only JSON
  line per launch, no status field, no attempt to track migrated/alive state in the file
  itself — `tmux has-session` is the only trustworthy liveness check, always re-derived
  live, never read out of the manifest.
- Everything below this entry (2026-08-11 through 2026-08-18) documents the OLD
  deep-link-at-launch design's failure modes and fixes. Most of the specific bugs
  (transcript-identification race, non-breaking-space prompt matching, Stop-hook
  turn-completion mechanism, login-expired detection) still apply directly and were
  carried over into the new scripts unchanged. The parts that don't carry over: anything
  about the deep-link import happening at launch time, the seed-turn/two-phase split, the
  1-hour watchdog, and step 4's disk-patch-then-restart permission-mode fix (already
  removed as a *separate*, earlier decision the same day — see the "Step 4 ... removed"
  entry just below this one — before this remote-control redesign happened on top of it).

## Step 4 (the disk-patch-then-restart permission-mode fix) removed as a mandatory step — user preference, 2026-08-20

Explicit user request: "get rid of 4, I don't like having to force claude desktop to
restart, I'll just manually adjust permissions when I see the session popup." Implemented
by deleting the mandatory `fix-session-timestamps.py` step from `rules.md`/`README.md`'s
numbered recipe (old step 4; deliver-task is now step 4, Done is now step 5) and
rewording every cross-reference in both docs and both scripts.

**Read this before ever proposing to re-add a mandatory step-4-equivalent.** Earlier
entries in this file (2026-08-11, 2026-08-14) record that "step 4 is optional" was tried
once before, by omission rather than by request, and caused the exact "sessions keep
coming up in Manual mode" symptom to be reported three separate times — the fix at the
time was to make the disk patch *mandatory*, not to drop it. **This time is different in
kind, not just degree:** it's an explicit, informed user tradeoff (accepting Manual mode
by default in exchange for never being asked to restart), not a docs gap an agent
stumbled into — and it's backed by the 2026-08-14 finding that the disk-patch-then-restart
design was never actually the best fix anyway: `LocalSessionManager.setPermissionMode`
(the same call the UI's permission-mode chip makes) updates the live session and disk
atomically, with **no restart required at all**. So "click the chip" isn't a downgrade
from the old mandatory step — per that entry's own conclusion, it's the *correct*
no-restart fix that the skill just hadn't wired up as its default path yet. Don't revert
this without the user asking first.

**What changed concretely:**
- `rules.md`'s numbered recipe: old step 4 deleted outright; old steps 5/6 renumbered to
  4/5. Every "until step 4 patches it" / "step-4 patch" reference now reads "until you
  manually set it from Desktop's UI" instead.
- `README.md`: the "## Step 4 (mandatory...)" section replaced with "## Fixing
  permission-mode without a restart (no script needed)," which explains the UI-chip path
  as primary and demotes `fix-session-timestamps.py` to an optional tool for two narrower
  cases: correcting sidebar chronological sort order (`createdAt`/`lastActivityAt`, still
  cosmetic-only and still needs an eventual restart to show up) and batch-copying
  model/effort/permissionMode across a backlog of older sessions in one pass.
- `bootstrap-session.sh`/`deliver-task.sh` comments reworded to match; the scripts'
  actual behavior is unchanged (neither one ever called `fix-session-timestamps.py`
  itself — that was always a separate, agent-invoked step), so this was a docs-only
  change plus keeping the script itself intact and available.
- `fix-session-timestamps.py` was NOT deleted — still correct and useful for the two
  narrower cases above, just no longer invoked by default.

**Known consequence worth restating plainly:** every session this skill bootstraps now
sits in `permissionMode: default` (Manual) — and with no `model`/`effort` set on its
registry entry either — until the user manually sets it from Desktop's UI. This is the
accepted tradeoff, not a bug to "fix" by re-adding the patch step.

## Split into two phases (fast seed turn + registration, then the real task) — 2026-08-18

User-reported friction: the single-phase design sent the real task as the bootstrap's
initial prompt, so a slow task delayed everything downstream of it — the sidebar entry,
the real title, and the permission-mode patch all sat gated behind however long that task
took to finish, even though none of those three actually depend on the task's own content.

**Fix:** `bootstrap-session.sh` now sends a fixed, pinned, throwaway seed prompt ("you are
bootstrapped from parent session '<title>' — do no work, invoke no skills, reply with
exactly: READY") instead of the real task, waits on a short ~70s hard-fail timeout (not
the 10-minute budget a real task needs), registers off of that, and — this is the part
that required rethinking the original script's teardown — **does not `/exit` or kill the
tmux pane afterward.** It leaves `claude` running idle and prints the tmux session name
alongside the UUID. A new companion script, `deliver-task.sh <tmux-name> <prompt>`, sends
the real task into that same still-open pane once titling (step 3) and the permission-mode
patch (step 4) are done, waits the original 10-minute budget, then does the `/exit` +
`tmux kill-session` teardown the original script used to do immediately.

**Why the same pane, not a fresh `claude --resume` or a Desktop-side message.** Consulted
before implementing (advisor call, this session): the tmux-launched process is the only
one carrying the inherited `--model`/`--effort`/`--permission-mode` flags. Delivering the
real task any other way — a fresh `claude --resume <uuid>` process, or a
`ccd_session_mgmt` message straight to the registry entry — would run against the
deep-link import's hardcoded `permissionMode: default`, which doesn't take effect as
`bypassPermissions` (or whatever the calling session actually runs as) until step 4's
patch survives a full Desktop restart. A task needing any tool approval would hang on the
first one, in a session with no live human to click "yes."

**Bug this reintroduced and had to guard against: sentinel reuse across two processes.**
The original script's Stop-hook sentinel path was keyed by its own `$$` — fine when one
script owned the whole lifecycle. `deliver-task.sh` runs as a separate process later and
has no way to know a prior script's `$$`, so the sentinel is now keyed by the **tmux
session name** instead (the one identifier both scripts share). `deliver-task.sh` also
defensively `rm -f`s the sentinel before sending the real task — without this, a leftover
sentinel from the seed turn makes the wait loop return instantly and send `/exit` mid-task,
which is exactly the truncated-turn failure mode from the 2026-08-11 entry below,
reintroduced by the split rather than actually new.

**Side benefit: closes a previously-documented gap for free.** The old single-phase
script's failure mode for a login-expired session (2026-08-13 entry below) was to ride out
the full 10-minute timeout (since the Stop hook never fires on a bare "Login expired"
error) and then register the dead session anyway with just a warning. Now that the seed
turn has its own short timeout and a hard `fail()` path that never opens the deep link,
that exact failure surfaces in ~70 seconds and nothing dead gets registered. This wasn't
the original ask, but the phase split happened to make it a natural side effect —
documented separately from the fix that motivated it so a future reader doesn't conflate
"why the split happened" with "what it also fixed along the way."

**New risk this trades in, flagged rather than solved — and narrower than first stated.**
The session is now visible and clickable in Desktop's sidebar *while the real task is
still running* in `deliver-task.sh` — registration (step 2) now happens well before task
completion (step 5), where it used to happen after. The first pass at this doc claimed
"opening the tab" itself spawns a competing Desktop process — that was an unverified
carry-over from the advisor's read, stated more confidently than the evidence supported.
Corrected after the user pushed back on it directly: `get_session` was confirmed live to
return `isRunning: false` for this session for the entire time the tmux process was
actually running, meaning Desktop's own registry has zero awareness that a tmux-driven
process exists at all. That's evidence that passively opening/viewing the tab likely just
renders the on-disk transcript — no process spawn. The actual risk is narrower: **typing
a new message into that tab and sending it** before `deliver-task.sh` finishes, which
would make Desktop spawn its own resume process to handle the turn, racing the
tmux-driven one on the same transcript file. This narrower scenario itself still hasn't
been live-tested (only reasoned from the `isRunning: false` evidence) — don't present it
as more confirmed than that in future summaries. Tell the user: viewing the tab is fine,
don't type into it until `deliver-task.sh` reports done.

**Guard against an orphaned pane if `deliver-task.sh` is never called:** a background,
disowned `(sleep 3600; tmux kill-session ...)` in `bootstrap-session.sh` kills the idle
pane after an hour. Chosen over leaving it running indefinitely — the whole design already
accepts "leave a live process around longer than the original single-phase script did";
letting it leak forever on top of that if the calling agent crashes or forgets step 5
seemed like the wrong default.

## Live end-to-end verification of the two-phase split, same day, 2026-08-18

Ran the real scripts against a scratch dir from inside a Desktop-hosted session (so
inheritance actually had a live calling session to read from), not just a syntax check.

**Phase 1 timing, confirmed:** `bootstrap-session.sh` completed — seed turn sent, Stop
hook fired, transcript located, deep-link opened, pane left alive — in **~7 seconds**
(`time` output: `6.903 total`). This is the concrete number behind "steps 1-4 finish in
well under a minute regardless of the real task" above; previously that same window was
gated behind however long the real task's own turn took.

**Model/effort/permissionMode inheritance for the CLI process itself, confirmed live:**
the printed line `Inheriting from calling session: --model claude-sonnet-5 --effort high
--permission-mode bypassPermissions` matched the calling session's actual registry
values, and phase 2's task (a `Write` tool call — something that needs permission
approval) completed without hanging, confirming the tmux-launched process really was
running under the inherited `bypassPermissions`, not CLI defaults.

**Phase 2 correctly appends to the same transcript rather than forking, confirmed by
reading the raw `.jsonl`:** all four turns — seed prompt, `READY` reply, real task
prompt, `Write` tool_use + tool_result, `DONE` reply — landed in the one transcript file
matching the UUID phase 1 printed. This directly confirms the advisor-flagged risk
("verify resume appends rather than forking before relying on this") never materialized,
because the design never re-enters via `claude --resume` at all — it sends into the
still-open pane, which was the right call.

**New finding that revises a previous entry: Claude Desktop `1.32352.0` (up from
`1.28929.0` when the "hardcodes `permissionMode: Default`, omits `model`" entry below was
written) now populates `model` correctly on deep-link import** — the registry entry
showed `"model": "claude-sonnet-5"`, matching what was actually inherited, not omitted.
**But `permissionMode` is still hardcoded, now to `"acceptEdits"` instead of `"default"`**
— neither the CLI's actual runtime mode (`bypassPermissions`, confirmed working per
above) nor the user's global `settings.json` default (also `bypassPermissions`, checked
directly) matches `"acceptEdits"`. Net effect for this skill: **step 4 (the
`fix-session-timestamps.py` patch) is exactly as mandatory as before** — confirmed by
running it and watching it correct `permissionMode: 'acceptEdits' -> 'bypassPermissions'`
— only the specific wrong value being patched has changed. Don't assume a future Desktop
version update has made step 4 optional without re-checking a fresh registry entry
directly; this is the second time the exact hardcoded value has shifted across an app
update while the underlying "still hardcoded, still wrong, still needs the disk patch"
shape stayed the same.

**Bug found and fixed by this same test:** `deliver-task.sh`'s success path (`/exit` +
`tmux kill-session`) never removed the Stop-hook sentinel file — confirmed a stray
`/tmp/claude-bootstrap-stopmark-<tmux-name>` file survived a fully successful run. Mostly
harmless (a new bootstrap uses a different tmux name, hence a different sentinel path)
but sloppy and an unnecessary trap for a future same-named retry; added `rm -f
"$STOP_SENTINEL"` after `cleanup` on the success path.

**Sandbox artifact worth recording so a future test doesn't waste time re-diagnosing it:**
verifying the phase-2 `Write` tool call's file via this harness's own sandboxed `Bash`
tool (even with `dangerouslyDisableSandbox: true`) returned "No such file or directory"
against the *nested-looking* scratchpad path (the one this harness presents, with real
`/` separators), even though the transcript showed the tool reporting success. The file
was real — found instantly via `find / -name <file>`, which surfaced it under a
*flattened, hyphen-joined* version of the same path (`/private/tmp/claude-501/-Users-...-
scratchpad/`, no nested directories at all). The tmux server, once detached, apparently
persists on the real filesystem using that flat naming, while this harness's own Bash
tool presents a nested-looking virtual view of the same location. Don't conclude "the
write failed" from a not-found on the nested path alone if this harness's sandbox is in
the picture — cross-check with `find /` (or just trust the tool_result in the transcript,
which was accurate here) before reporting a false negative.


## The disk-patch-then-restart design (step 4) is architecturally unable to fix the symptom the user actually experiences — confirmed 2026-08-14

Third report of "sessions still always come up in Manual" despite the 2026-08-11 fix
(doc reworded to make the disk patch mandatory, 4-session backlog patched). Root cause
this time isn't a doc gap or a skipped step — it's the mechanism itself: `saveSession()`
writes `permissionMode` to disk, but the **running app's in-memory `SessionManager` map
is what's actually served**, and that only re-hydrates from disk on a full app restart
(re-confirmed directly: `get_session` on a session patched hours earlier still showed
the pre-patch value). This user's Desktop process (`ps aux`) had been running
continuously since the prior Wednesday with no restart — so every disk patch queued
since then, across multiple bootstrapped sessions, sat inert. "Restart whenever
convenient" is not a real mitigation for a user who keeps Desktop open for days between
restarts; from their seat the bug never goes away, because the fix never takes effect
before the next session gets created and reported broken again.

**A live, no-restart fix path exists in the app itself, confirmed in source
(`app.asar`, v1.28929.0):** `LocalSessionManager.setPermissionMode(sessionId, mode)` —
the same method the UI calls when you click the permission-mode chip in a session's
input bar — looks up the session by ID in the in-memory map, calls
`session.query.setPermissionMode(mode)` if a live query exists (harmless no-op check if
not), sets `session.permissionMode = mode` directly, and calls `saveSession()` — i.e. it
updates memory and disk together, atomically, with no restart required. This is *not* a
theoretical read of the code: the exact IPC handler is registered as
`e.ipc.handle('$eipc_message$_<build-uuid>_$_claude.web_$_LocalSessions_$_setPermissionMode', ...)`,
invoked from the renderer via `ipcRenderer.invoke(...)`. **The embedded UUID segment is
build-namespaced and will change on the next Desktop update** — never hardcode that
channel string in a script; it would silently break on the next auto-update.

**Why this isn't wired up yet:** the method is renderer-only (called from the UI, not
exposed as a CLI flag, MCP tool, or any other externally-callable surface). Checked and
ruled out reaching it directly: `ps aux | grep remote-debugging` on the live `Claude`
process found no CDP debug port open, so there's no external-automation hook into
Electron's devtools protocol either.

**Superseded below — UI automation is not actually the best no-restart path.** At the
time this was written, UI automation (focus the tab, click the chip) looked like the only
option. A second, better mechanism was found and empirically confirmed the same day: see
"A second, correct-from-birth path" below. Keep the UI-automation option in mind only as
a fallback for the case that path doesn't cover (an *instant* bootstrap) — don't build it
as the primary fix.

**Not yet built, and not attempted live this session:** confirmed via `list_sessions`
that this user routinely has 2+ sessions `isRunning: true` concurrently (other agents
mid-turn) at the moment this was investigated, and watched the visibly-focused tab
change out from under a `claude://resume` deep-link call between two screenshots ~90s
apart with no action taken in between — something else in the running app (likely one of
those concurrent sessions) is changing which tab is frontmost on its own. Blind
coordinate/frontmost-based UI automation against this app is therefore unsafe to attempt
opportunistically: a click aimed at "whichever tab is focused right now" can land on a
live, unrelated, in-progress session instead of the intended target. Any future
automation of this fix must positively identify the target session's own window/tab
element (e.g. by the title `set_session_title` just gave it) via the accessibility tree
before clicking anything — never assume frontmost == the session just bootstrapped.

**Also confirmed while investigating:** `claude://resume?session=<uuid>` on an
*already-registered* session (not a fresh import) does not reliably bring that session's
tab to the front — called it against a known idle, untitled, already-registered session
and the visibly active tab afterward was a different, unrelated session. Don't rely on
the deep link as a "focus this existing session" mechanism; it's confirmed (see entry
below) to only reliably do first-time registration.

**Interim guidance until the live-fix step is built:** don't keep treating step 4's disk
patch as sufficient. Either (a) tell the user which new session(s) are affected and that
a 2-second manual click of that session's permission-mode chip fixes it instantly with no
restart, or (b) if/when a restart is genuinely happening soon anyway, let step 4's patch
ride along with it. Don't promise "fixed" based on the disk write alone — that phrasing
is exactly what generated reports #2 and #3 of the same symptom.

## A second, correct-from-birth path exists: route through `scheduled-tasks`, not the deep-link recovery import — confirmed empirically 2026-08-17

The question that started this: is there anything we can do *before* a session is first
loaded into Desktop, so it never hits the hardcoded-`Default` state at all, instead of
patching it (live or on disk) after the fact? Yes — and it's not theoretical.

Sampled 26 existing sessions with a `scheduledTaskId` field (i.e. created by the
`scheduled-tasks` MCP server firing a task, not by this skill's tmux+deep-link recipe):
**zero exceptions**, all showed the user's real default `permissionMode`/`model`, never
`Default`/`None`. That alone was only correlational (this user's global default happens
to be `bypassPermissions`, so it couldn't distinguish "reads the global default" from
"copies whatever session created the task"). Ran the actual probe advisor recommended
instead of trusting the correlation: created a real one-time `create_scheduled_task`
(`fireAt` ~3 min out, trivial prompt), waited for it to fire, then `get_session` on the
resulting session before deleting the task. Result, directly observed:
`permissionMode: "bypassPermissions"`, `model: "claude-sonnet-5"` — correct from the
`createdAt` timestamp itself, no patch, no restart, no click. It also got a real
content-derived title ("Probe permission inheritance"), not a copy of the static task
description — so title quality isn't a regression either.

**Why this path is immune to the deep-link bug:** the deep-link/`claude://resume`
mechanism's bug is specifically in its "recover an orphaned CLI transcript" code path,
which constructs a brand-new registry entry with `permissionMode` hardcoded in the object
literal — never reads any settings file. A scheduled task, by contrast, has Desktop
launch a fresh `claude` CLI process directly (the same way any normal terminal-launched
session would), so it resolves `~/.claude/settings.json`'s `permissions.defaultMode`
normally, the same as every other non-recovered session already does. Two structurally
different session-creation code paths in the app; only one is broken.

**One nuance worth being explicit about:** a scheduled-task firing has no "calling
session" at all (it's a cron/timer trigger, not a user action), so this can only be
reading the *global* default — it cannot be inheriting a specific calling session's mode
the way this skill's own step 4 tries to (`--from <uuid>` / `CLAUDE_CODE_HOST_SESSION_ID`
copy). That's a fine substitute only because this user's global default already matches
what every session should have (`bypassPermissions`) — if a future bootstrap ever needed
to intentionally launch in a *non-default* mode, this path can't do that; the tmux recipe
still can (via explicit `--permission-mode` flags).

**What this is not:** a drop-in replacement for `bootstrap-session.sh`. `fireAt` must be
a future timestamp (no "run now" exists via MCP), so the practical floor is roughly a
minute-plus of latency plus a poll/notification wait, versus the tmux recipe's
seconds-later "session exists with a completed turn." This is a second mechanism for
"queue a session for me to pick up shortly," not a fix to the existing "bootstrap one
right now" recipe — the deep-link path (and its Default-hardcoding bug) is still what
runs for an instant bootstrap, and still needs either the one-click chip fix or a
restart. Don't retire the tmux+deep-link recipe over this finding.

## Pre-writing the registry file before the first `claude://resume` does NOT survive the import — empirically confirmed, don't re-attempt, 2026-08-17

Tempting idea: since `sessionId` for a freshly-recovered session is deterministic
(`local_` + the CLI transcript's own session UUID — confirmed by cross-referencing a
real bootstrapped session's `sessionId`/`cliSessionId` fields, and by the `let
d=\`${P.r}${s.cliSessionId}\`` line in `recoverCliSessions`'s own source), the
destination filename is knowable *before* ever calling the deep link. So: pre-write
`local_<uuid>.json` with the desired `permissionMode` at that exact path first, then
call `claude://resume?session=<uuid>` — does the import respect/merge what's already
there?

**Tested for real, not reasoned about.** Ran a disposable tmux+`claude` turn (same
mechanics as `bootstrap-session.sh`) to get a genuine orphan CLI transcript UUID, then
*before* opening the deep link, hand-wrote a full, schema-shaped registry JSON at the
exact predicted path with `permissionMode: "bypassPermissions"`, a marker `title`,
`model`, and `effort` all set. Then ran `open "claude://resume?session=<uuid>"` and
re-read the file.

**Result: completely clobbered, not merged.** Every field from the pre-write was gone —
`permissionMode` back to `"default"`, `title`/`model`/`effort` entirely absent (not just
reset — removed), `createdAt` a fresh "now" timestamp instead of the pre-written one. The
recovery function doesn't check disk for an existing file at the destination path at
all — it unconditionally builds a brand-new object from CLI-transcript metadata alone and
does a full-object `saveSession()` write, clobbering whatever was already sitting there.
The `this.sessions.has(d)` in-memory guard is the *only* pre-check that path has; a
same-path file that isn't yet in the in-memory map might as well not exist.

**Conclusion: there is no way to seed a session's permission mode ahead of its first
`claude://resume` call.** This closes out the "intervene before first load" line of
investigation for real — the hardcoded-`Default` write happens exactly once, at
first-ever recovery, unconditionally, and nothing said or written beforehand changes it.
The only two levers that actually work are still: fix it after (chip click, live and
immediate; or disk patch + restart), or avoid this code path entirely (scheduled-tasks,
at the cost of the mandatory task-creation approval and latency documented above). Don't
re-attempt a pre-write variant of this idea — it's not a matter of getting the schema
more precise, the code never reads the file in the first place.

**Correction, 2026-08-18 — the "safe no-op on an already-loaded session" claim below this
entry was wrong, or at least incomplete.** Re-opening `claude://resume` on a session
that's already the *focused* tab is a safe no-op (verified: tested against this
conversation's own live session, nothing changed, not even `lastFocusedAt`). But calling
it on an already-loaded session that ISN'T currently focused is a real, destructive
action, not a no-op: it forces a focus-switch to that session, and a focus-switch
re-persists whatever's currently in memory back to disk — silently destroying any pending
external disk patch to that session (confirmed directly: patched `cwd`/`originCwd` on
disk, called the deep link on that unfocused session, and the patch was gone, overwritten
by the stale in-memory values, with zero change to the in-memory state itself). This is
the same mechanism the "don't open/focus before restart" warning elsewhere in this file
already describes for the permission-mode patch — it turns out to apply to a plain
`claude://resume` call too, not just literally clicking the tab. Don't treat "it's already
imported, so the deep link is harmless" as true in general — it depends entirely on
whether the target is already focused.

**Correction, same day, caught by the user:** the paragraph above under-weighted a cost
that flips the recommendation. `create_scheduled_task` (and `delete_scheduled_task`)
carry a hardcoded `"This tool requires explicit approval regardless of permission
mode"` — confirmed directly in the tool's own permission-prompt UI, screenshotted by the
user. My own "clean" re-test of this (create then delete, both returned without erroring)
was a bad test: I only checked whether the call *errored*, not whether a prompt appeared
and was answered — the user was simply present and clicked both prompts fast enough that
I couldn't tell from the tool result alone. Don't repeat that mistake: "the tool call
returned successfully" is not evidence a permission prompt didn't fire, only that if one
did, someone answered it. To actually test whether a tool bypasses approval, the
description/schema is the ground truth to check first (it said so explicitly here), and
a live test only means something if you can positively confirm no UI prompt rendered —
absence of an error is not that confirmation.

**Net effect: scheduled-tasks is not the lower-friction path — it's higher-friction,**
because its one required click is a **mandatory, blocking gate on task creation itself**
(nothing happens without it, no override), whereas the tmux+deep-link recipe's
permission-mode fix is a **click that's optional and deferrable** — the session already
exists and has already completed its seeded turn before that click would ever happen; it
only matters for *future* turns run through Desktop's own UI, and can be put off
indefinitely or batched across many sessions into one restart. Recommendation reversed:
default to tmux+deep-link even knowing it leaves `permissionMode: default` behind; don't
route through scheduled-tasks to "avoid a click" — it doesn't avoid one, it just moves a
smaller, deferrable click earlier and turns it into a mandatory, blocking one, and adds
a latency floor on top. Scheduled-tasks remains the right tool for its actual purpose
(genuinely time-deferred or recurring work) — just not as a permission-mode workaround.

## "Wait for the turn to finish" text-matching is a dead end for good — replaced with content-stability, 2026-08-06

Live-tested three successive approaches to detecting turn completion in the tmux pane
before landing on one that actually works; each intermediate one *looked* fixed after a
quick check and then failed on the next real run. Recorded so the next person (or agent)
doesn't re-walk this exact path:

1. **Whole-pane `grep '^❯'`** (the original script): false-positived on a stale idle
   prompt still visible on screen from *before* the prompt was submitted. Sent `/exit`
   2.4s after prompt submission, before the assistant had even started — the resulting
   transcript had zero assistant messages, and the file the prompt asked for was never
   created. Silent failure: the script printed a UUID and exited 0.
2. **Anchor to the last line + require a busy-keyword match first**
   (`esc to interrupt|Nucleating|Crunched|Thinking|Running`): fixed (1), but then hung
   the full 90-iteration/180s timeout on the very next run. CLI `2.1.223`'s actual
   busy/spinner wording (`"Cogitated for Ns"`, `"Brewed for Ns"`, `"Sautéed for Ns"`,
   `"Symbioting…"`, `"Churned for Ns"` — it rotates through food/biology-themed verbs)
   matches none of those hardcoded strings, so the debounce gate never opened. Busy-text
   matching is fundamentally not viable — the CLI's spinner vocabulary rotates and will
   keep drifting out from under any hardcoded list.
3. **Exact whole-pane byte-equality across two 2-second-apart polls** (no text matching
   at all): also hung the full timeout. Root cause found via a manual probe session
   (`tmux new-session` + direct `capture-pane` polling, no script involved): the CLI's
   own footer rotates independent hint text (`"... /effort"` vs `"Advisor Tool
   (experimental) is on and may use more tokens · /advisor"`) every few seconds even at
   genuine idle, and the token/cost readout in that same footer ticks live too. Neither
   is a busy signal; both make exact whole-pane equality fail essentially forever.
4. **What actually works**: the TUI always renders a fixed input box — a full-width `─`
   separator line, an input line starting with "❯", then another `─` separator — with
   everything below that (model/dir, tokens/cost, permission hint, rotating tip) being
   exactly the volatile footer identified in (3). Locate the last such separator pair
   and compare only the content *above* it across polls. This deliberately excludes the
   volatile footer (so its rotation/ticking can't block detection) while still catching
   a genuinely busy state, since a live spinner line changes that content every render.
   Verified end-to-end: a single-tool-call prompt finished in 19s (no timeout warning),
   and a multi-tool-call prompt (create two files, then read both back) also finished
   cleanly with a real final assistant response in the transcript, no false-early-exit.

**Also confirmed, and deliberately dropped**: gating "done" on the input line itself
being blank. It's a red herring in both directions — the input line stays blank
(`"❯"` + trailing U+00A0, not ASCII space) throughout a genuinely busy turn (the spinner
renders as its own line in the content above, not in the input line), and *post-turn*
the CLI's "prompt suggestions" feature can populate the input line with a real suggested
follow-up command (e.g. `"❯ cat ok.txt"`) while already fully idle — gating on
blank-input would then never fire once a suggestion appears.

## `grep`'s BRE `\{n,\}` silently breaks on multi-byte characters under this script's real (locale-unset) execution environment — and ad hoc interactive testing hid it for hours

The separator-detection regex in the fix above, `grep -n '^─\{5,\}$'`, tested correctly
*every single time* in ad hoc interactive shell commands, then silently matched **zero**
lines on every one of 90 poll iterations when the actual script ran standalone
(confirmed via a temporary debug instrumentation that dumped per-iteration state to
stderr). Root cause, confirmed with a byte-for-byte repro comparing environments: this
execution context has `LANG`/`LC_ALL` unset, and under the resulting C/POSIX locale,
plain BSD grep's BRE `\{5,\}` counts repetitions of the single byte immediately
preceding it — the *last byte* of "─"'s 3-byte UTF-8 encoding, not the whole character —
so it actually matches 5+ repeats of one stray byte, which the real footer text never
contains (`grep -n '^─\{5,\}$'` against a real 7-`─`-character line: exit 0 under an
explicit UTF-8 locale, exit 1 under `LANG= LC_ALL=C`, byte-for-byte identical input).

The reason ad hoc testing never caught this: `type grep` in an interactive agent shell
here reveals a **shell function** the harness installs that shadows plain `grep` with a
call into its own Unicode-aware `ugrep` binary. That shim is invisible to a plain
`bash scriptfile` subprocess invocation, which only ever sees real BSD grep — so every
"let me just test this regex real quick" during development silently ran against a
completely different regex engine than the one the shipped script actually uses.
**Don't validate a script's shell-command behavior by running the same command ad hoc in
an interactive agent shell — run the actual script.** Shell functions/aliases aren't
inherited by a separate script invocation regardless of matching environment variables.

Fix: replace the regex entirely with `[ -n "$line" ] && [ -z "${line//─/}" ]` — bash's
own literal-pattern parameter substitution, not a regex quantifier, so there's no
byte-vs-character repeat-count ambiguity to depend on locale for in the first place.

## The CLI's idle prompt line ends in a non-breaking space, not a regular space

`tmux capture-pane -p` on the `❯ ` idle prompt returns bytes `E2 9D AF C2 A0` — the
angle-quote glyph followed by `U+00A0` (non-breaking space), not `U+0020`. A regex like
`^❯ *$` (literal ASCII space) silently never matches, and any polling loop built on it
hangs until its own timeout with no useful error. Anchor on `^❯` alone (start only) when
detecting "REPL is idle" from captured pane text — don't try to also assert end-of-line
emptiness via a plain space class.

## Confirmed: `claude://resume?session=<uuid>` registers a session live, no app restart

This directly refines a claim in `claude-desktop-internals/README.md` ("registry is read
ONLY at app startup"). That's true for the raw-registry-file-write path documented
there, but false for the `claude://resume` URL-scheme path — Desktop's own handler
imports and registers on the spot. Found by testing both back to back on the same
session: `get_session` returned "not found" and no registry file existed on disk right
after a tmux-bootstrapped turn finished; one `open "claude://resume?session=..."` later,
`get_session` returned a full record. Don't re-derive "does this need a restart" from
scratch for future Desktop-registration questions — check which of the two paths
(registry-file-write vs. deep-link) is actually in play first.

## Source of the deep-link mechanism: the user's own Raycast extension

`~/workspace/personal/raycast_scripts/claude-session-search` (a tool John built himself)
already implements the reopen half of this (`src/search-sessions.tsx` →
`openInClaudeDesktop()`) and the title-derivation half
(`tools/title-untitled-sessions.py`). When investigating "how do I get X to show up in
the Desktop sidebar," check this extension's source before re-deriving the mechanism from
the app's own minified bundle — it's already been reverse-engineered once, with working
code and comments explaining the non-obvious parts (e.g. the `openId` vs `sessionId`
distinction for ~20%-old-scheme sessions).

## Fixing the deep-link's timestamp side effect needs a restart — confirmed, not just theorized

Patched `createdAt`/`lastActivityAt` directly in a session's registry file (real
transcript timestamps, computed via `fix-session-timestamps.py`) immediately after that
session had been deep-link-imported and titled. Called `get_session` (MCP) right after
the disk write, with zero other interactions in between: it still returned the old "now"
timestamps, unchanged. This is direct confirmation (not an inference from the docs) that
a live-loaded session's in-memory state, not its on-disk registry file, is what the
running app actually serves — the fix requires an app restart to take effect, no
exceptions found. Don't assume a disk patch to a *just-imported* session is any more
"live" than a patch to a long-idle one; both need the same restart.

## `ls -t "$dir"/*.jsonl | head -1` misidentifies the new session when another live session shares the same cwd — confirmed incident, 2026-08-06

`bootstrap-session.sh`'s "locate the transcript this session just wrote" step assumes the
most-recently-modified `.jsonl` under the project dir is the one the script's own tmux
`claude` process just created. That's false whenever a **different, genuinely live**
session in the same cwd is also being actively used at that moment — its ongoing writes
can out-race the freshly-spawned session's own first write, so the script picks up the
wrong file entirely.

Confirmed by directly observing it happen: bootstrapping two sessions back-to-back
(Jon Mak, then Scott Lee QPR-prep sessions, both `cwd=eng_ai_assistant`) both had the
script report the *same* UUID — which turned out to be an unrelated, real, concurrently-
active session (the user asking about Ferdium refresh behavior in a different window on
the same project dir). Consequence: `set_session_title` was called against that live
session (renamed to "QPR FY27Q1 — Jon Mak", clobbering its real title) and a second
bootstrap's `open claude://resume` never registered the *actual* new session at all. The
real new sessions had, in fact, been created correctly — their transcripts existed on disk
with the right seeded first message — the script just never found them because a
newer-mtime unrelated file won the `ls -t` race.

**`eng_ai_assistant` is an unusually bad cwd for this heuristic** — the user runs many
concurrent Claude sessions against this same project directory routinely (background
pollers, PR-shepherd, parallel agent work), so a same-cwd collision here is *likely*, not
a rare edge case.

**Recovery pattern that worked**: instead of trusting the script's printed UUID, verify
independently — `grep -l "<the exact seed text>" ~/.claude/projects/<encoded-cwd>/*.jsonl`
(excluding your own current session's transcript, which will also match if you typed the
seed text into a Bash tool call to invoke the script) finds the real transcript
unambiguously, since the seed prompt text is unique. Then manually run
`open "claude://resume?session=<correct-uuid>"` and `set_session_title` against the
verified-correct ID. Also rename any session you mistakenly retitled back to something
content-accurate — there is no "undo," the previous title (if `titleSource: auto`) isn't
recoverable from the registry, only re-derivable by reading the transcript yourself.

**Not yet fixed at the script level**: the robust fix is to snapshot the set of existing
`.jsonl` filenames in the target dir *before* launching tmux, then after the turn
completes, select the file that's new relative to that snapshot (set difference) rather
than newest-by-mtime. Until `bootstrap-session.sh` is patched this way, treat its printed
UUID as unverified when bootstrapping into a cwd with other likely-concurrent sessions —
confirm with the grep pattern above before registering/titling.

## Deep-link import hardcodes `permissionMode: Default` and omits `model` — confirmed in source, 2026-08-06

The recurring symptom ("bootstrapped sessions always show up in Manual mode") wasn't a
settings-propagation bug — `~/.claude/settings.json`'s `permissions.defaultMode:
"bypassPermissions"` is irrelevant to it. Read `app.asar` via `strings -a` (per
`claude-desktop-internals`'s own "verify in source before black-box trial-and-error"
rule) and found the exact function: the `claude://resume` deep-link's "recover CLI
session" path logs `"Recovered CLI session ${cliSessionId} as ${f}"` and constructs the
new registry entry with `permissionMode:o.C.Default` hardcoded and no `model`/`effort`
key in the object literal at all — independent of whatever CLI flags the tmux-launched
process actually ran with. Cross-checked against every session this skill has ever
bootstrapped: `permissionMode` was `"default"` and `model` was `None`/absent on all of
them, with zero exceptions, confirming the hardcoding empirically as well as in source.

Also checked whether `permissionMode` merely *displays* something, in case patching it
would be cosmetic: found the `ka(e.permissionMode, "persistedToActive")` call path,
which validates the persisted value against `new Set(Object.values(PermissionMode))` and
passes it through unchanged if valid (only warns-and-drops on an unrecognized string) —
this runs when a persisted session becomes active again, e.g. full-app hydration. So a
disk patch to `permissionMode` **is** functional, not display-only, once the app
restarts and hydrates it.

Fix shipped two ways since the bug is two separate points: (1) `bootstrap-session.sh` now
auto-detects the calling session's own model/effort/permissionMode (from its
`CLAUDE_CODE_HOST_SESSION_ID` registry entry) and passes them as `claude` CLI flags for
the live tmux-driven turn — this also matters functionally, not just cosmetically: a
prompt needing tool approval under a Manual-mode tmux process would hang the
"wait for turn to finish" poll forever, since `send-keys` can't click a permission
dialog. (2) `fix-session-timestamps.py` now also copies model/effort/permissionMode into
the persisted registry entry (same batched/no-focus/restart-required mechanism it
already used for timestamps) — since the deep-link import ignores the live CLI flags
from (1) entirely when writing the *persisted* record.

## The `ls -t` newest-mtime race (documented below) got a real fix once a second write depended on the same UUID

Adding the model/effort/permissionMode write above raised the stakes on the
already-known "wrong UUID from a concurrent same-cwd session" bug (see below): a
misidentified UUID would now silently overwrite an unrelated live session's model and
permission mode, not just its title. `bootstrap-session.sh` now snapshots
`<project-dir>/*.jsonl` before launching tmux and diffs against the post-turn listing to
find the genuinely-new file, falling back to (and warning about) newest-mtime only when
the diff is ambiguous (zero or multiple new files).

## `set_session_title` worked immediately post-import, unprompted by focus state

`claude-desktop-internals`'s dead-ends section warns that patching a registry file
directly is clobbered if the session is the currently-focused tab. Calling the actual
`set_session_title` MCP tool (not a raw file patch) right after a deep-link import — with
the session never having been opened as a tab at all — worked cleanly both times tested.
This is a different code path (goes through the live `SessionManager`, not a bypassed
file write), so the "don't patch a focused session's file" caveat doesn't transfer to it;
don't assume the MCP tool has the same restriction without re-testing if a similar
"not found" or "silently ignored" symptom shows up.

## Render-inference for turn completion is a dead end, full stop — 2026-08-11

User-reported symptom: the bootstrapped session's initial prompt sometimes (not always)
never finished executing — the script sent `/exit` while the agent was still mid-turn,
producing a session that shows the seeded prompt followed by a truncated/absent response.
The content-stability approach documented above (2026-08-06 entry, "What actually works")
was the culprit, and this closes out that entire family of approaches rather than
patching it again.

**Root cause, confirmed by direct live measurement, not inference:** launched a real
`claude --effort high` session in tmux, gave it a pure-reasoning prompt (no tools, forced
to "think" silently before producing any visible text), and sampled `tmux capture-pane -p`
every 2 seconds while genuinely busy. The captured content (specifically the line showing
elapsed thinking time, e.g. `"Baked for 37s"`) sat **byte-identical across 11 consecutive
2-second polls — 22+ seconds** — before changing again, while the turn was still
unambiguously in progress (confirmed by watching it eventually resume and complete
correctly). This is the CLI's own terminal-repaint cadence stalling, not a busy/idle
signal at all. Since a real stall this long was observed directly, **no finite
content-stability window is safe** — raising the required consecutive-match count (the
obvious "fix") only raises the false-positive threshold, it never closes the hole,
because reasoning turns can go silent for minutes. Any future contributor tempted to bump
the debounce count or add a settle-and-reconfirm window: this was tried in the design
sense and rejected — see the advisor consultation in this session's transcript for the
reasoning. Do not re-attempt a variant of render-diffing; the whole approach is unsound.

**Checked whether the transcript `.jsonl` could be the live signal instead** (append-only,
in theory immune to render timing). Also confirmed dead by direct measurement: polled
`wc -l` on the transcript every 2 seconds during a real turn, both while the CLI was
silently "thinking" (flat at 19 lines for 40+ seconds) *and* while it was actively
streaming visible response text into the pane (flat at 28 lines for another 40+ seconds).
The CLI batches its transcript writes in a way that doesn't correlate with real-time
visible progress — confirmed empirically, not theorized — so polling file growth is just
as blind to "is it still working" as polling the pane.

**What actually works: a Stop hook.** Claude Code already supports a `Stop` hook
(the user's own `~/.claude/settings.json` uses one for a sound+notification when a turn
ends) that fires exactly once, deterministically, when the main-agent turn genuinely
finishes — confirmed this is a real, already-relied-upon mechanism before building on it.
Registered a second, disposable one scoped to just the bootstrap invocation via
`claude --settings '<json>'` (this flag layers additional settings without needing to
touch the target repo's own `.claude/settings.local.json` or the user's global file), with
a hook command that `touch`es a sentinel file — skipping subagent `Stop` events via the
same `agent_type`-presence check the user's own existing hook already uses. `bash
bootstrap-session.sh` (the actual script, not an ad hoc probe — this repo has a standing
lesson about the two not being equivalent) now just polls for that sentinel file's
existence instead of diffing pane content.

Verified end-to-end, with the real script, twice:
1. A pure-thinking prompt that stayed silent for 80+ seconds before producing any visible
   text — sentinel appeared the instant the real response completed, transcript confirmed
   the full final answer was present (no truncation).
2. A multi-tool-call prompt (three `Write` + three `Read` calls) — sentinel appeared
   exactly once, after the *last* tool call and the final summary, not after any
   individual tool call in between.

Both runs were the literal `bootstrap-session.sh` script end-to-end (including the
UUID-detection and `claude://resume` registration steps), not a standalone tmux probe —
confirmed the transcript's final assistant message ended with the exact expected marker
text in both cases.

## Framing step 4 as "optional"/"occasional cleanup" was the actual root cause of the recurring Manual-mode symptom — 2026-08-11

User-reported symptom: "sessions from this skill keep showing up in Manual permission
mode" persisted well after the model/effort/permissionMode copy logic (above) was built
and confirmed working. The script was never the problem. Checked live registry state
across the last ~7 days of bootstrapped sessions and found several — including ones from
the day before this was reported — sitting at `permissionMode: "default"`/`model: None`
indefinitely. Root cause: both `rules.md` and `README.md` explicitly told the executing
agent to treat `fix-session-timestamps.py` as optional (`README.md` literally said
"Step 4 (optional)" and "worth doing as an occasional batch cleanup, not after every
single bootstrapped session"; `rules.md`'s numbered recipe ended at step 4 with "Done —
no cleanup needed" *before* ever mentioning the fix, which only appeared afterward under
a separate "Known side effects" heading). An agent following the numbered recipe
literally, as instructed, correctly stops before ever reaching the fix.

Fix: reworded both docs so running the fix script is step 4 of the mandatory numbered
recipe (not a footnote reachable only by reading past "Done"), and split the two costs
that were being conflated: the disk-only script run (cheap, safe, do it **every time**
right after titling) vs. the app restart that actually applies the patch (genuinely
disruptive, batch it, user-triggered only). Only the restart needs to stay occasional/
batched — the write to disk that queues the fix should never be skipped, since nothing
else ever revisits an unfixed session to queue it later.

## The tmux-spawned `claude` process can hit a stale login independent of the caller's own session (2026-08-13)

Two consecutive bootstrap attempts (different `cwd`, different tmux session names, same
target directory `~/workspace/mcpproxy`) both produced a transcript with exactly one
assistant turn: `Login expired · Please run /login` — the spawned session never even
started the requested work. Both times the script itself reported success: it hit the
10-minute Stop-hook-sentinel timeout (since a login-expired session never fires the
hook), printed its "couldn't confirm the turn finished" warning, then proceeded anyway
to find the session's UUID and open the `claude://resume` deep link — registering a
dead, empty session in the sidebar as if it were a real one.

**Root cause not fully diagnosed yet** — plausible candidates: the plain `claude` REPL
launched fresh in a brand-new tmux pane doesn't reliably inherit the same live
credential/session state as an already-running Desktop-hosted `claude` process, even
though both should read the same on-disk auth config. Two-for-two on the same target
directory suggests it's tied to that `cwd`/config rather than a one-off token race —
but this wasn't confirmed against a *different* target directory in the same window, so
don't treat "systemic for this skill" as proven yet — treat it as "systemic for this
specific case" until reproduced (or not) elsewhere.

**This is the same failure shape as an OAuth flow that needs a human-completed browser
step** (see `skills/mcp-proxy/`'s docs on why headless `auth login` can't finish a cold
login) — a login/auth refresh that requires interactive completion cannot be finished by
a scripted `send-keys` driver. The user resolved it by opening the resumed session in
Desktop directly and running `/login` themselves.

**Process gap to fix:** the script's "turn didn't finish, but I'll register it anyway"
fallback should distinguish *"still working, ran long"* from *"never started at all"* —
e.g. check the transcript for at least one non-error assistant message before opening
the deep link, and if the only assistant turn is a bare error string, report failure
loudly instead of silently registering a dead session. Don't run steps 3/4
(title/timestamp patch) on a session confirmed to be in this state — there's nothing
real to title, and if the user is about to open/drive it manually to fix the login,
patching first would just get clobbered per the existing "don't focus before the
restart" warning above.

## "Session opens in the wrong project" — ruled out a Desktop-side cause, fixed at the argument source instead, 2026-08-17

User-reported symptom: "every once in a while" a bootstrapped session shows up grouped
under a different project in Desktop's sidebar than the one that invoked it. Before
touching anything, checked whether Desktop re-derives or remaps `cwd` at import time
(which would make this a Desktop bug no amount of script discipline could fix): compared
every real session where `sessionId == "local_" + cliSessionId` (i.e. a genuine
first-time deep-link import) against the `cwd` recorded in that session's own CLI
transcript's first line. **1361 checked, 0 mismatches.** Desktop always uses the CLI
transcript's own `cwd` verbatim; it never remaps it after the fact. This rules out a
Desktop-side cause definitively — the wrong project was always coming from whatever
`<target-cwd>` argument got passed to `bootstrap-session.sh` at invocation time.

**Fix, informed by this skill's own history of documentation-only fixes not holding**
(the permission-mode step-4 saga above was reported three times despite reworded docs):
made the safe path the lazy path instead of just writing a rule. `bootstrap-session.sh`
now accepts a `--same-project` sentinel for `<target-cwd>` that resolves to the *calling*
session's own registry `cwd` (the same `CLAUDE_CODE_HOST_SESSION_ID` lookup already used
for model/effort/permissionMode inheritance — hoisted earlier in the script so both uses
share one lookup). rules.md and README.md now say to pass this sentinel by default,
explicit paths only when the user actually names a different target.

**Deliberately did not use `$PWD`** as the source of truth, and don't let a future edit
substitute it in "for simplicity" — this script's own shell cwd (and any orchestrating
agent's) drifts constantly across worktrees, submodules, and scratchpad dirs, none of
which reflect what project a session is grouped under in the sidebar. The registry `cwd`
of the calling session's own entry is the only value that byte-matches that grouping.

**Deliberately did not add a mismatch warning** (print a warning if the passed `<cwd>`
differs from the calling session's own) — considered and rejected: the script has no way
to distinguish an intentional cross-project bootstrap (legitimate and common for this
user — e.g. bootstrapping a `dealia` session from an `eng_ai_assistant` one) from
accidental drift, so it would fire on both, train the reader to ignore it, and land on
stderr where nothing reads it anyway. The sentinel fixes the actual failure mode (an
agent guessing/inferring a path) without needing to police explicit, deliberate paths.

## Session worked in the right worktree but lost eng_ai_assistant context — a different problem than the wrong-project bug above, 2026-08-17

**Superseded 2026-08-18 — see "The 'flip it' design" entry below.** The prescription in
this entry (cwd = the worktree, `--add-dir` = the calling project) solved the context-loss
problem but not the sidebar-grouping complaint that came right after it — the user still
wanted the session grouped under `eng_ai_assistant`, which this design can't do since
`cwd` is what drives that grouping and this design points `cwd` at the worktree on
purpose. The direction is inverted in the superseding entry: `cwd` stays
`--same-project`, and the worktree is granted via `BOOTSTRAP_EXTRA_DIR` instead. Keep
reading below for why `--add-dir` itself is still exactly the right primitive — only
which side gets added flipped.

Immediately after shipping the `--same-project` fix above, the user pointed at a real
incident that looked similar but wasn't: a "Starcraft video static fade animation"
session (cwd `eng_ai_assistant`) bootstrapped a new Desktop session at
`~/workspace/wc-worktrees/sc-static-clear-fade` — a git worktree in a completely separate
repo — after the user explicitly asked for "a new claude desktop session in a watercooler
git worktree." Read the transcript tail to confirm: the script call passed that exact
explicit path, matching what was asked. **This was not the wrong-project bug** — an
explicit path when the user names a different target is exactly correct per the rule
above, and Desktop grouping the resulting session under "watercooler" in the sidebar was
a correct, direct consequence of that real cwd, not a misfire.

What the user actually wanted, once asked to clarify: keep the work happening in the
watercooler worktree, but don't lose eng_ai_assistant's own context (skills,
skill-routing, docs, learnings) just because the session's cwd points elsewhere. This is
a real gap, distinct from the cwd-selection bug: Claude Code discovers `CLAUDE.md` by
walking up from `cwd`, and a sibling directory (a separate top-level worktree, not nested
under `eng_ai_assistant`) is never on that path, so the bootstrapped session genuinely had
no access to `eng_ai_assistant`'s `CLAUDE.md`/`skills/`/`docs/` at all.

**Fix confirmed via `claude --help`, not assumed:** `--add-dir <dir>` is documented
there — in the `--bare` flag's own description, which lists it as one of the ways to
provide context when normal auto-discovery is off — as bringing in "CLAUDE.md dirs", not
just tool access. `bootstrap-session.sh` now auto-adds `--add-dir <calling project's
own cwd>` whenever the resolved target cwd differs from it (i.e. whenever an explicit,
different-project path was used) — verified via a dry run of just the resolution logic
that it fires exactly when expected (different project) and stays empty for the
`--same-project` case (nothing to add, since they're the same directory already).
`BOOTSTRAP_NO_ADD_DIR=1` opts out for a genuinely clean-room bootstrap.

**Don't conflate this with the wrong-project fix** if a future report sounds similar —
diagnose first which one it actually is: check whether the `<target-cwd>` passed to the
script was explicit-and-intentional (this gap: context, not location) or
guessed/inferred (the earlier bug: location itself was wrong). The fixes are additive,
not alternatives — both apply to their respective failure mode.

## The "flip it" design: keep cwd as --same-project always, grant the worktree via BOOTSTRAP_EXTRA_DIR instead — 2026-08-18

The entry above fixed context-loss but the user came back: a fresh bootstrap into
`wc-worktrees/wc-offices` (explicit path, matching what was asked) was still grouped under
"watercooler," and this time that itself was the complaint — "I don't want that to ever
happen... all sessions should be invoked in the same project as the parent." Before
building anything, walked through several real, live experiments rather than guessing at
the app's minified source (each one cheap, decisive, and worth recording so none gets
re-attempted):

1. **Confirmed watercooler worktrees are technically part of `eng_ai_assistant`'s own git
   tree** — `git rev-parse --git-common-dir` from inside `wc-worktrees/wc-offices` resolves
   to `eng_ai_assistant/.git/modules/repos/taxcred/watercooler/code/watercooler` (a
   submodule). Conceptually "the same project," but this doesn't change what Desktop
   displays — see next.
2. **The registry schema has no separate "project"/"group" field at all** — only
   `cwd`/`originCwd`. Whatever drives the sidebar label, it isn't a stored value
   independent of those two.
3. **User's hypothesis, tested directly and confirmed: `cwd`/`originCwd` *are* what the
   sidebar groups by.** Captured a session's in-memory (`get_session`) and on-disk state,
   asked the user to manually drag it to the `eng_ai_assistant` group in Desktop's own UI,
   then re-captured both. Diff: `cwd` and `originCwd` both flipped from the watercooler
   worktree to `eng_ai_assistant`, live, no restart needed — this is a genuine live IPC
   action (`LocalSessions.changeCwd`/`changeSessionCwd`, confirmed present in the app's own
   IPC handler list alongside `setPermissionMode`), not a cosmetic relabel.
4. **But that same UI action mutates `permissionMode` and `effort` as side effects** — the
   diff also showed `permissionMode: bypassPermissions → acceptEdits` and `effort: "high"`
   disappearing entirely. "Move to project" isn't a pure regrouping; it's closer to
   re-associating the session with a different directory's own defaults. Also: it changes
   `cwd`, meaning a session moved this way would actually try to *run its next turn* in
   the new directory — exactly wrong for a session with real, in-progress work in the
   worktree it was moved out of.
5. **Tried a manual disk patch instead** (`cwd` back to the worktree, `originCwd` left as
   `eng_ai_assistant`, to test whether they're independently meaningful) — then, per the
   user's suggestion, tried firing `claude://resume` on that same session to see if it
   would "force a reload from disk." **It didn't reload anything — it clobbered the
   patch**, overwriting both fields back to the stale in-memory value (`eng_ai_assistant`)
   with zero change to memory itself. This is the focus-switch-destroys-pending-patches
   mechanism documented in the correction above, caught here in the act on a real,
   non-test session — see that correction for why this matters beyond this one incident.
6. **User explicitly ruled out a full app restart as a remedy** — "extremely disruptive,
   we often have many sessions running at the same time." This closed off the only
   mechanism (short of the live UI action, which has its own side effects) that could ever
   apply a disk patch. Registry-level cwd manipulation was abandoned at this point, not
   just deprioritized — there is no remaining lever in that direction that doesn't require
   either a live focus event (destroys patches) or a restart (ruled out).

**The actual fix, proposed by the user:** don't touch the session's own `cwd` at all — launch
with `cwd` = the calling project (`--same-project`, correct grouping from birth, zero
registry manipulation, zero restart dependency), and separately grant the agent access to
the worktree via `--add-dir`, with the real task prompt explicitly naming that directory
as where the actual work happens. This inverts the direction of the 2026-08-17 `--add-dir`
fix (which added the calling project to a worktree-rooted session) — now the worktree gets
added to a calling-project-rooted session instead.

**Verified empirically before shipping, per the standing rule that a live test beats
reasoning about `--add-dir`'s documented scope.** The open risk: `--add-dir`'s own
description says "additional directories to allow tool access to" — does that cover
`Bash` commands run with a `cd` into the added directory (`git`, `npm test`, etc.), or only
absolute-path `Read`/`Edit`? Launched a throwaway tmux `claude` with `-c
<scratchpad>` and `--add-dir <wc-worktrees/wc-offices>`, and a prompt to `cd` into the
added directory, run `git status`/`git rev-parse --show-toplevel`/`ls`, write a file, and
read it back. **All of it worked** — `cd`, `git`, and file writes all functioned normally
inside the added directory; the CLI's own footer even correctly tracked it as `wc-offices
⎇ design/office-doors`. No second "trust this folder" dialog fired for the added
directory in this case (already-trusted from prior use — the existing dismiss-loop would
catch one regardless, since it matches the string generically, not by directory).

**Shipped:** `bootstrap-session.sh` gained `BOOTSTRAP_EXTRA_DIR` (mirrors the existing
`BOOTSTRAP_NO_ADD_DIR` env-var convention rather than a new positional arg — zero
signature change, nothing to break for existing callers). The existing `HOST_CWD`
cross-project `--add-dir` logic (2026-08-17 entry) is untouched and still correct for its
own case — a genuinely different top-level project like dealia, where a different sidebar
grouping is actually wanted. The two mechanisms are complementary, not competing: which
one applies depends on whether the target directory should register as its own project or
not.

**Also fixed as part of this:** a dangling test session (`local_10683cb0...`, real
in-progress "Office-doors redesign" work) was left with a stale, never-applied disk patch
from step 5's testing (`cwd` pointing at the worktree, `originCwd` at `eng_ai_assistant`,
in-memory still at `eng_ai_assistant`). Reset both fields on disk to match where its real
work actually lives (the worktree) before moving on — an inconsistent patch nobody will
remember the provenance of a week from now is exactly the kind of landmine this file
exists to prevent.
