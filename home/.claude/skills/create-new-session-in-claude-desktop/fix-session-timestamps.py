#!/usr/bin/env python3
"""
Fix a Desktop-imported session's registry side effects: createdAt/
lastActivityAt (stamped to "now" on import) and model/effort/permissionMode
(hardcoded to Default/omitted on import, regardless of what the bootstrap
turn actually ran with).

Why: `claude://resume?session=<uuid>` (the bootstrap-session.sh deep-link
step) creates a fresh registry entry via the app's "recover CLI session"
path. Confirmed directly in the app's own source (not inferred): that path
stamps createdAt/lastActivityAt to "now" and hardcodes
`permissionMode: Default`, omitting `model`/`effort` entirely — regardless
of what --model/--effort/--permission-mode flags the CLI process itself was
launched with. This script rewrites all of the above using two sources of
truth:
  - createdAt/lastActivityAt: the transcript's own first/last message
    timestamps.
  - model/effort/permissionMode: another session's registry entry — by
    default, the *calling* session's (via CLAUDE_CODE_HOST_SESSION_ID), i.e.
    "make the new session match whatever I'm running as right now". Pass
    --from to copy from a different session instead, or --no-settings to
    skip this part and fix timestamps only.

The permissionMode field is NOT cosmetic — confirmed in the app's source
that it's read back (via a `persistedToActive` validation against the known
PermissionMode enum, no extra gate) whenever a persisted session becomes
active again, e.g. on the next Desktop hydration. Writing "bypassPermissions"
here is honored the same as if the user had set it themselves.

IMPORTANT — this only takes effect after a full Claude Desktop quit+relaunch.
The running app's in-memory SessionManager is the source of truth while it's
alive (see ~/.claude/skills/claude-desktop-internals/README.md); it does not re-read a
session's registry file mid-run. Run this, do NOT open/focus the affected
session's tab in the meantime (that re-persists the in-memory state and
clobbers this patch), then quit and relaunch Desktop so it hydrates fresh
from disk.

Usage:
    python3 fix-session-timestamps.py <session-uuid> [<session-uuid> ...]
    python3 fix-session-timestamps.py --dry-run <session-uuid> ...
    python3 fix-session-timestamps.py --from <source-uuid> <session-uuid> ...
    python3 fix-session-timestamps.py --no-settings <session-uuid> ...
"""
import glob
import json
import os
import sys
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
PROJ = os.path.join(HOME, ".claude", "projects")
DESK = os.path.join(HOME, "Library", "Application Support", "Claude", "claude-code-sessions")


def iso_to_ms(s):
    dt = datetime.strptime(s, "%Y-%m-%dT%H:%M:%S.%fZ").replace(tzinfo=timezone.utc)
    return int(dt.timestamp() * 1000)


def transcript_path(uuid):
    hits = glob.glob(os.path.join(PROJ, "*", f"{uuid}.jsonl"))
    return hits[0] if hits else None


def registry_path(uuid):
    hits = glob.glob(os.path.join(DESK, "*", "*", f"local_{uuid}.json"))
    return hits[0] if hits else None


def real_bounds(path):
    """First/last message timestamp (ms) found in the transcript."""
    first = last = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                o = json.loads(line)
            except json.JSONDecodeError:
                continue
            ts = o.get("timestamp")
            if isinstance(ts, str):
                try:
                    ms = iso_to_ms(ts)
                except ValueError:
                    continue
                if first is None:
                    first = ms
                last = ms
    return first, last


def host_session_uuid():
    """Default settings source: the calling session, from its own env var."""
    host = os.environ.get("CLAUDE_CODE_HOST_SESSION_ID")
    if not host:
        return None
    return host[len("local_"):] if host.startswith("local_") else host


def main():
    args = sys.argv[1:]
    dry_run = "--dry-run" in args
    no_settings = "--no-settings" in args
    args = [a for a in args if a not in ("--dry-run", "--no-settings")]

    settings_source = None
    if "--from" in args:
        i = args.index("--from")
        try:
            settings_source = args[i + 1]
        except IndexError:
            print("--from requires a session uuid", file=sys.stderr)
            sys.exit(1)
        del args[i:i + 2]
    elif not no_settings:
        settings_source = host_session_uuid()

    uuids = args
    if not uuids:
        print(__doc__)
        sys.exit(1)

    settings = {}
    if settings_source:
        src_reg = registry_path(settings_source)
        if not src_reg:
            print(f"WARNING: --from/host session {settings_source} has no registry "
                  f"entry under {DESK} — skipping model/effort/permissionMode copy.",
                  file=sys.stderr)
        else:
            with open(src_reg, encoding="utf-8") as f:
                src = json.load(f)
            for key in ("model", "effort", "permissionMode"):
                if src.get(key):
                    settings[key] = src[key]
            if settings:
                print(f"Copying settings from {settings_source} ({src.get('title', '(untitled)')!r}): "
                      f"{settings}")
            else:
                print(f"WARNING: source session {settings_source} has no model/effort/"
                      f"permissionMode set — nothing to copy.", file=sys.stderr)
    elif not no_settings:
        print("WARNING: no --from given and CLAUDE_CODE_HOST_SESSION_ID is unset — "
              "skipping model/effort/permissionMode copy (timestamps only).",
              file=sys.stderr)

    for uuid in uuids:
        tpath = transcript_path(uuid)
        rpath = registry_path(uuid)
        if not tpath:
            print(f"[{uuid}] SKIP: no transcript found under {PROJ}")
            continue
        if not rpath:
            print(f"[{uuid}] SKIP: no registry entry found under {DESK} "
                  f"(session was never opened in Desktop)")
            continue

        first_ms, last_ms = real_bounds(tpath)
        if first_ms is None:
            print(f"[{uuid}] SKIP: no timestamped messages in transcript")
            continue

        with open(rpath, encoding="utf-8") as f:
            reg = json.load(f)

        old_created = reg.get("createdAt")
        old_activity = reg.get("lastActivityAt")
        print(f"[{uuid}] {reg.get('title', '(untitled)')!r}")
        print(f"    createdAt:      {old_created} -> {first_ms}")
        print(f"    lastActivityAt: {old_activity} -> {last_ms}")
        for key, new_val in settings.items():
            print(f"    {key}: {reg.get(key)!r} -> {new_val!r}")

        if dry_run:
            print("    (dry run — not written)")
            continue

        reg["createdAt"] = first_ms
        reg["lastActivityAt"] = last_ms
        reg.update(settings)
        with open(rpath, "w", encoding="utf-8") as f:
            json.dump(reg, f)
        print(f"    written to {rpath}")

    print()
    print("Reminder: this only takes effect after a full Claude Desktop quit+relaunch.")
    print("Don't open/focus the affected session's tab before restarting — that")
    print("re-persists the in-memory 'now' value and overwrites this patch.")


if __name__ == "__main__":
    main()
