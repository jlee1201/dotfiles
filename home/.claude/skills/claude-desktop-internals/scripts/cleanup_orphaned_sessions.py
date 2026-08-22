#!/usr/bin/env python3
"""Find/remove Claude Desktop sidebar entries whose transcript no longer exists on disk.

The (formerly 30-day) cleanupPeriodDays retention setting deletes a session's
.jsonl transcript but does NOT clean up its registry entry -- leaving a real,
titled sidebar row that opens to empty/broken content. See ../README.md
"Ghost / orphaned sidebar entries".

Only ever touches registry entries with ZERO matching transcript -- never
deletes anything that has real content on disk. A registry file that fails
to parse as JSON is reported separately and is NEVER auto-deleted by
`archive` (only `delete --include-unreadable` will remove it) -- it is not
a confirmed orphan, just unreadable, and those are different problems.

Usage:
  python3 cleanup_orphaned_sessions.py scan                     # report only, no changes
  python3 cleanup_orphaned_sessions.py archive                  # set isArchived: true (recoverable)
  python3 cleanup_orphaned_sessions.py delete                   # remove the registry file entirely
  python3 cleanup_orphaned_sessions.py archive --filter TEXT    # only entries whose title contains TEXT
  python3 cleanup_orphaned_sessions.py delete --include-unreadable  # also remove unparseable registry files

IMPORTANT: quit Claude Desktop FIRST, then run this, then relaunch. The app
persists its own in-memory session state back to these same registry files;
running this while it's open risks a race where the app overwrites your
change (or, worse, this script's TOCTOU-checked orphan list goes stale mid-run
because the app is concurrently writing). See ../README.md.
"""
import json
import os
import subprocess
import argparse
from pathlib import Path

REGISTRY_ROOT = Path.home() / "Library/Application Support/Claude/claude-code-sessions"
PROJECTS_ROOT = Path.home() / ".claude/projects"


def encode_cwd(cwd):
    return cwd.replace("/", "-").replace(".", "-").replace("_", "-")


def find_registry_dir():
    dirs = [d for d in REGISTRY_ROOT.glob("*/*") if d.is_dir()]
    if len(dirs) != 1:
        raise RuntimeError(f"expected exactly 1 registry bucket, found {len(dirs)}: {dirs}")
    return dirs[0]


def desktop_is_running():
    try:
        out = subprocess.run(["pgrep", "-f", "Claude.app/Contents/MacOS/Claude"],
                              capture_output=True, text=True, timeout=3)
        return bool(out.stdout.strip())
    except Exception:
        return False  # can't tell -- don't block on an inconclusive check


def find_orphans(filter_text=None):
    """Returns (orphans, unreadable) -- two separate lists. `orphans` entries
    are (path, parsed_dict, title); `unreadable` entries are just paths."""
    registry_dir = find_registry_dir()
    orphans, unreadable = [], []
    for f in registry_dir.glob("local_*.json"):
        try:
            d = json.loads(f.read_text())
        except Exception:
            unreadable.append(f)
            continue
        cid, cwd, title = d.get("cliSessionId"), d.get("cwd", ""), d.get("title", "")
        if not cid or not cwd:
            continue
        if filter_text and filter_text.lower() not in (title or "").lower():
            continue
        jsonl = PROJECTS_ROOT / encode_cwd(cwd) / f"{cid}.jsonl"
        if not jsonl.exists():
            orphans.append((f, d, title))
    return orphans, unreadable


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mode", choices=["scan", "archive", "delete"])
    parser.add_argument("--filter", default=None, help="Only act on entries whose title contains this text")
    parser.add_argument("--include-unreadable", action="store_true",
                         help="delete mode only: also remove registry files that failed to parse as JSON")
    args = parser.parse_args()

    if args.mode != "scan" and desktop_is_running():
        print("Claude Desktop appears to be running. Quit it first -- the app can overwrite "
              "this script's changes to registry files it still has loaded (see README.md). "
              "Re-run once it's closed.")
        return 1

    orphans, unreadable = find_orphans(args.filter)
    print(f"found {len(orphans)} orphaned registry entries" + (f" matching '{args.filter}'" if args.filter else ""))
    if unreadable:
        note = " (title unknown -- --filter cannot apply to these)" if args.filter else ""
        print(f"found {len(unreadable)} UNREADABLE registry files{note} -- never auto-archived, "
              f"only removed by 'delete --include-unreadable'")

    if args.mode == "scan":
        for f, d, title in orphans[:50]:
            print(f"  {f.name}  ->  {title!r}")
        if len(orphans) > 50:
            print(f"  ... and {len(orphans) - 50} more orphans")
        for f in unreadable[:20]:
            print(f"  UNREADABLE  {f.name}")
        if len(unreadable) > 20:
            print(f"  ... and {len(unreadable) - 20} more unreadable")
        return 0

    acted = 0
    for f, d, title in orphans:
        # re-check right before acting -- the desktop app (or a concurrent run)
        # could have written a real transcript for this session since the scan above
        cid, cwd = d.get("cliSessionId"), d.get("cwd", "")
        jsonl = PROJECTS_ROOT / encode_cwd(cwd) / f"{cid}.jsonl"
        if jsonl.exists():
            continue  # no longer an orphan -- leave it alone
        if args.mode == "archive":
            d["isArchived"] = True
            tmp = f.with_suffix(".tmp")
            tmp.write_text(json.dumps(d))
            os.replace(tmp, f)
        elif args.mode == "delete":
            f.unlink()
        acted += 1

    unreadable_acted = 0
    if args.mode == "delete" and args.include_unreadable:
        for f in unreadable:
            f.unlink()
            unreadable_acted += 1

    print(f"{args.mode}d {acted} orphaned entries" +
          (f" + {unreadable_acted} unreadable entries" if unreadable_acted else "") +
          ". Fully quit (if not already) and relaunch Claude Desktop to see the change.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
