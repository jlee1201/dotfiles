#!/usr/bin/env python3
"""Import Cursor IDE chat history into Claude Desktop as real, resumable sessions.

Writes both files a session needs (see ../README.md for why both are required):
  1. Transcript:      ~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl
  2. Registry entry:  ~/Library/Application Support/Claude/claude-code-sessions/<bucket>/local_<sessionId>.json

No model calls, no `claude --resume` touch, no live process. Batch as many
sessions as you want, then do ONE full quit+relaunch of Claude Desktop to
make them all appear at once.

Usage:
  # Single chat
  python3 import_cursor_sessions.py single <cursor-chat-id> "<title>" <target-repo-path> [--dry-run]

  # Batch, from a JSON file: {"<cursor-chat-id>": "<target-repo-path>", ...}
  # Titles are looked up from Cursor's own DB by chat id.
  python3 import_cursor_sessions.py batch <mapping.json> [--dry-run]

  # List Cursor chats (id, name, message count) to find IDs to import
  python3 import_cursor_sessions.py list [--search TEXT] [--limit N]
"""
import sqlite3
import json
import sys
import os
import re
import uuid as uuidlib
import subprocess
import base64
import argparse
from pathlib import Path
from datetime import datetime, timezone

DB_PATH = Path.home() / "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
PROJECTS_ROOT = Path.home() / ".claude/projects"
REGISTRY_ROOT = Path.home() / "Library/Application Support/Claude/claude-code-sessions"
CLI_VERSION_HINT = "2.1.219"  # last verified; not load-bearing, purely informational
SAFE_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,128}$")


def find_registry_dir():
    dirs = [d for d in REGISTRY_ROOT.glob("*/*") if d.is_dir()]
    if len(dirs) != 1:
        raise RuntimeError(
            f"expected exactly 1 registry bucket under {REGISTRY_ROOT}, found {len(dirs)}: {dirs}. "
            "Claude Desktop internals may have changed shape -- see ../README.md 'How to re-verify'."
        )
    return dirs[0]


def desktop_is_running():
    try:
        out = subprocess.run(["pgrep", "-f", "Claude.app/Contents/MacOS/Claude"],
                              capture_output=True, text=True, timeout=3)
        return bool(out.stdout.strip())
    except Exception:
        return False  # can't tell -- don't block on an inconclusive check


def atomic_write(path, content_str):
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(content_str)
    os.replace(tmp, path)


def encode_cwd(cwd):
    return cwd.replace("/", "-").replace(".", "-").replace("_", "-")


def git_branch(repo, cache=None):
    if cache is not None and repo in cache:
        return cache[repo]
    branch = None
    try:
        out = subprocess.run(
            ["git", "-C", repo, "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, timeout=3,
        )
        if out.returncode == 0:
            branch = out.stdout.strip()
    except Exception:
        pass
    if cache is not None:
        cache[repo] = branch
    return branch


def get_chat(cid, conn):
    """Fetch one chat's composer metadata + bubbles. `conn` must be a shared,
    already-open sqlite3 connection -- see ../learnings.md re: why opening a
    fresh connection per chat is catastrophically slow against this DB."""
    cur = conn.cursor()
    cur.execute("SELECT value FROM cursorDiskKV WHERE key = ?", (f"composerData:{cid}",))
    row = cur.fetchone()
    if row is None:
        return None, [], {}
    comp = json.loads(row[0])
    headers = comp.get("fullConversationHeadersOnly", [])
    cur.execute("SELECT key, value FROM cursorDiskKV WHERE key LIKE ?", (f"bubbleId:{cid}:%",))
    bubbles = {}
    for k, v in cur.fetchall():
        bid = k.split(":")[-1]
        try:
            bubbles[bid] = json.loads(v)
        except Exception:
            pass
    return comp, headers, bubbles


def iso_to_epoch_ms(ts):
    if ts is None:
        return None
    if isinstance(ts, (int, float)):
        return int(ts)
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        return int(dt.timestamp() * 1000)
    except Exception:
        return None


def load_images(bubble, warnings):
    """Cursor stores pasted/attached images as file paths (bubble.context.selectedImages),
    not inline base64 -- see ../learnings.md. Converts to Claude API image content blocks."""
    imgs = []
    for img in (bubble.get("context", {}) or {}).get("selectedImages", []) or []:
        path = img.get("path")
        if not path or not Path(path).exists():
            warnings.append(f"missing image file: {path}")
            continue
        try:
            data = Path(path).read_bytes()
        except Exception as e:
            warnings.append(f"failed to read image {path}: {e}")
            continue
        ext = Path(path).suffix.lower().lstrip(".")
        media_type = {
            "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
            "gif": "image/gif", "webp": "image/webp",
        }.get(ext, "image/png")
        imgs.append({
            "type": "image",
            "source": {"type": "base64", "media_type": media_type, "data": base64.b64encode(data).decode("ascii")},
        })
    return imgs


def synthesize(cid, name, repo, conn, dry_run=False, branch_cache=None):
    """Returns a dict: {status, n_turns, n_images, jsonl_path, registry_path, new_project, warnings}."""
    if not SAFE_ID_RE.match(cid):
        return {"status": "invalid_id", "detail": f"chat id {cid!r} doesn't look like a safe identifier"}

    proj_dir = PROJECTS_ROOT / encode_cwd(repo)
    jsonl_path = proj_dir / f"{cid}.jsonl"
    registry_path = find_registry_dir() / f"local_{cid}.json"

    jsonl_exists, registry_exists = jsonl_path.exists(), registry_path.exists()
    if jsonl_exists and registry_exists:
        return {"status": "skipped_exists", "jsonl_path": str(jsonl_path), "registry_path": str(registry_path)}
    if jsonl_exists or registry_exists:
        # exactly one of the two files exists -- a prior run was interrupted mid-write.
        # Don't guess: report it distinctly so the operator can inspect/clean up,
        # rather than silently treating it as either "done" or overwriting it.
        return {"status": "partial_state", "jsonl_path": str(jsonl_path), "registry_path": str(registry_path),
                "detail": "exactly one of the transcript/registry files exists -- a previous run "
                          "likely crashed mid-write; remove the stray file before retrying"}
    new_project = not proj_dir.exists()

    comp, headers, bubbles = get_chat(cid, conn)
    if comp is None:
        return {"status": "not_found"}
    branch = git_branch(repo, branch_cache)

    lines, warnings = [], []
    prev_uuid, n_written, n_images = None, 0, 0
    first_ts, last_ts = None, None

    for h in headers:
        b = bubbles.get(h.get("bubbleId"), {})
        btype = h.get("type")
        text = (b.get("text") or "").strip()
        images = load_images(b, warnings) if btype == 1 else []
        if not text and not images:
            continue
        ts = b.get("createdAt")
        if ts:
            first_ts = first_ts or ts
            last_ts = ts
        this_uuid = str(uuidlib.uuid4())

        if btype == 1:  # user
            content = (list(images) + ([{"type": "text", "text": text}] if text else [])) if images else text
            n_images += len(images)
            entry = {
                "parentUuid": prev_uuid, "isSidechain": False, "promptId": str(uuidlib.uuid4()),
                "type": "user", "message": {"role": "user", "content": content},
                "uuid": this_uuid, "timestamp": ts, "permissionMode": "bypassPermissions",
                "promptSource": "sdk", "userType": "external", "entrypoint": "claude-desktop",
                "cwd": repo, "sessionId": cid, "version": CLI_VERSION_HINT,
            }
            if branch:
                entry["gitBranch"] = branch
        else:  # assistant
            entry = {
                "parentUuid": prev_uuid, "isSidechain": False,
                "message": {
                    "model": "claude-sonnet-5", "id": f"msg_imported_{this_uuid[:24]}",
                    "type": "message", "role": "assistant",
                    "content": [{"type": "text", "text": text}],
                    "stop_reason": "end_turn", "stop_sequence": None, "stop_details": None,
                    "usage": {"input_tokens": 0, "cache_creation_input_tokens": 0,
                              "cache_read_input_tokens": 0, "output_tokens": 0},
                },
                "requestId": f"req_imported_{this_uuid[:24]}", "type": "assistant",
                "uuid": this_uuid, "timestamp": ts, "userType": "external", "entrypoint": "claude-desktop",
            }
        lines.append(entry)
        prev_uuid = this_uuid
        n_written += 1

    if n_written == 0:
        return {"status": "empty"}

    title = name if name.startswith("[c") else f"[c] {name}"

    if dry_run:
        return {"status": "dry_run", "n_turns": n_written, "n_images": n_images,
                "jsonl_path": str(jsonl_path), "registry_path": str(registry_path),
                "new_project": new_project, "warnings": warnings}

    proj_dir.mkdir(parents=True, exist_ok=True)
    transcript_lines = [json.dumps(l) for l in lines]
    transcript_lines.append(json.dumps({"type": "custom-title", "customTitle": title, "sessionId": cid}))
    atomic_write(jsonl_path, "\n".join(transcript_lines) + "\n")

    created_ms = iso_to_epoch_ms(first_ts) or iso_to_epoch_ms(comp.get("createdAt"))
    updated_ms = iso_to_epoch_ms(last_ts) or iso_to_epoch_ms(comp.get("lastUpdatedAt")) or created_ms

    registry_entry = {
        "sessionId": f"local_{cid}", "cliSessionId": cid, "cwd": repo, "originCwd": repo,
        "lastFocusedAt": updated_ms, "createdAt": created_ms, "lastActivityAt": updated_ms,
        "isArchived": False, "title": title, "titleSource": "auto", "permissionMode": "default",
        "remoteMcpServersConfig": [], "alwaysAllowedReasons": [], "sessionPermissionUpdates": [],
    }
    # write the registry entry LAST -- its existence is what makes the session
    # findable, so the transcript should always be fully in place first.
    atomic_write(registry_path, json.dumps(registry_entry))

    return {"status": "ok", "n_turns": n_written, "n_images": n_images,
            "jsonl_path": str(jsonl_path), "registry_path": str(registry_path),
            "new_project": new_project, "warnings": warnings}


def get_chat_name(cid, conn):
    cur = conn.cursor()
    cur.execute("SELECT value FROM cursorDiskKV WHERE key = ?", (f"composerData:{cid}",))
    row = cur.fetchone()
    if not row:
        return None
    return json.loads(row[0]).get("name")


def cmd_list(args):
    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    cur = conn.cursor()
    cur.execute("SELECT key, value FROM cursorDiskKV WHERE key LIKE 'composerData:%'")
    rows = []
    for k, v in cur.fetchall():
        try:
            d = json.loads(v)
        except Exception:
            continue
        name = d.get("name") or "(untitled)"
        if args.search and args.search.lower() not in name.lower():
            continue
        rows.append((k.split(":", 1)[1], name, len(d.get("fullConversationHeadersOnly", []))))
    for cid, name, n in rows[: args.limit]:
        print(f"{cid}  ({n:4d} msgs)  {name}")
    print(f"\n{len(rows)} matching chats" + (f" (showing {min(args.limit, len(rows))})" if len(rows) > args.limit else ""))


def _refuse_if_desktop_running(dry_run):
    if not dry_run and desktop_is_running():
        print("Claude Desktop is currently running. New sessions won't be visible until a "
              "restart anyway (see README.md), and a currently-open/live session's registry "
              "file can get silently overwritten by the app. Safe to proceed for NEW sessions "
              "not already open in the app, but prefer quitting first if unsure.", file=sys.stderr)


def cmd_single(args):
    _refuse_if_desktop_running(args.dry_run)
    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    result = synthesize(args.chat_id, args.title, args.repo, conn, dry_run=args.dry_run)
    print(json.dumps(result, indent=2))


def cmd_batch(args):
    _refuse_if_desktop_running(args.dry_run)
    mapping = json.load(open(args.mapping_file))
    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    branch_cache = {}
    summary = {"ok": 0, "skipped_exists": 0, "empty": 0, "not_found": 0, "dry_run": 0,
               "invalid_id": 0, "partial_state": 0, "error": 0,
               "images": 0, "new_project_dirs": [], "warnings": [], "errors": []}
    for i, (cid, repo) in enumerate(mapping.items()):
        try:
            name = get_chat_name(cid, conn) or cid
            result = synthesize(cid, name, repo, conn, dry_run=args.dry_run, branch_cache=branch_cache)
        except Exception as e:
            summary["error"] += 1
            summary["errors"].append((cid, f"{type(e).__name__}: {e}"))
            continue  # one bad chat must not abort the rest of the batch
        status = result["status"]
        summary[status] = summary.get(status, 0) + 1
        summary["images"] += result.get("n_images", 0)
        if result.get("new_project") and repo not in summary["new_project_dirs"]:
            summary["new_project_dirs"].append(repo)
        for w in result.get("warnings", []):
            summary["warnings"].append((cid, w))
        if (i + 1) % 50 == 0:
            print(f"progress: {i+1}/{len(mapping)}", file=sys.stderr)
    print(json.dumps(summary, indent=2))
    if summary["partial_state"]:
        print(f"\n{summary['partial_state']} chat(s) are in a partial state from an earlier "
              "interrupted run -- see the JSON output above, inspect and clean up manually before retrying.",
              file=sys.stderr)
    if not args.dry_run and summary["ok"] > 0:
        print("\nDone writing. Fully quit and relaunch Claude Desktop once to see the imported sessions.", file=sys.stderr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_list = sub.add_parser("list", help="List Cursor chats")
    p_list.add_argument("--search", default=None)
    p_list.add_argument("--limit", type=int, default=30)
    p_list.set_defaults(func=cmd_list)

    p_single = sub.add_parser("single", help="Import one chat")
    p_single.add_argument("chat_id")
    p_single.add_argument("title")
    p_single.add_argument("repo")
    p_single.add_argument("--dry-run", action="store_true")
    p_single.set_defaults(func=cmd_single)

    p_batch = sub.add_parser("batch", help="Import many chats from a {chat_id: repo} JSON mapping")
    p_batch.add_argument("mapping_file")
    p_batch.add_argument("--dry-run", action="store_true")
    p_batch.set_defaults(func=cmd_batch)

    args = parser.parse_args()
    args.func(args)
