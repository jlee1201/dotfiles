# Claude Desktop Internals — Learnings

> Accumulated edge cases and process lessons. Mechanism-level facts (the
> actual recipe, file schemas, dead ends) live in `README.md` — this file is
> for gotchas and how-to-work-on-this-effectively notes.

## Don't declare an undocumented mechanism "impossible" or "required" after 1-2 failed attempts

Several conclusions stated as settled facts during the 2026-07-28 Cursor→Claude
import investigation were later directly reversed:

- "Raw registry file writes are never honored by the running app" — only true
  for a session **already loaded** into live memory (e.g. a focused tab). A
  session the app has never loaded reads its registry file fresh from disk
  the next time it restarts.
- "Passive file-based discovery doesn't exist" — it does (the search
  scanner), it's just a separate code path from the sidebar/registry system.
- "The `--resume` touch is required to make a session visible" — backwards;
  it's specifically what *causes* the two failure modes (stray process,
  now-stamped dates) that made sessions look broken.

Each of these was believed after 2-3 black-box tests failed. The actual
answer was found in minutes once the app's own bundled source was read (see
README → "How to re-verify"). **Escalate to reading the source well before
the 3rd or 4th black-box attempt on an undocumented mechanism** — this is
the concrete case behind the "theories vs. proven facts" rule in
`docs/coding-standards.md`, extended to negative/impossibility claims too.

## Cursor bubble data gotchas (source side, for the importer)

- A bubble's `text` field can be empty even when the bubble represents a real
  turn (tool-call-only or thinking-only content) — skip bubbles with no text
  **and** no images, don't count them as turns.
- Pasted/attached images live at `bubble.context.selectedImages[].path` — an
  actual file path under Cursor's own `workspaceStorage/<hash>/images/`
  directory, not inline base64. The top-level `images` field on a bubble was
  empty in every sample checked (5000+ bubbles) — don't rely on it.
- Image files referenced this way can be missing if Cursor's own cache was
  cleaned — check existence before reading, don't hard-fail the whole import
  over one missing image (see the script's `warnings` list).
- `bubble.createdAt` is real per-message ISO8601 — use it for both the
  transcript entry `timestamp` *and* the registry `createdAt`/`lastActivityAt`
  derivation. Don't fall back to the composer-level `createdAt`/`lastUpdatedAt`
  unless no bubble timestamps exist at all.

## Performance: Cursor's `state.vscdb` is a multi-GB SQLite file — never open a connection per item

`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` was
7.85 GB with 788k+ rows in `cursorDiskKV` in this environment. A per-chat
`sqlite3.connect()` + query loop over ~800 chats projected to **~4 hours**;
switching to one shared connection reused across the whole loop brought real
per-item queries down to a stabilized ~15s/item (~3.3 hours for 794 items —
still slow, apparently inherent to random B-tree page reads against an
uncached multi-GB file, but the extra per-connection overhead had made an
already-slow operation slower still). This exact "bulk-query once, don't
loop per-item" lesson had *already* been learned once earlier in the same
investigation (for checkpoint-file resolution) but wasn't carried over to
the later synthesis batch — a reminder to re-apply a mid-session lesson to
every subsequent piece of code that touches the same resource, not just the
step where it was first discovered. See also
`docs/cross-skill-learnings.md` → "Reuse connections/clients across loops".

## `cwd` encoding collisions are a real risk at scale

`encode_cwd` replaces `/`, `.`, and `_` with `-`, which is lossy — e.g.
`workspace/eng_ai_assistant` and a hypothetical `workspace/eng-ai-assistant`
would collide. Before writing into a repo's project directory, verify the
encoded path matches an *existing* `~/.claude/projects/<dir>` rather than
trusting the transform blind, and treat "this would create a brand-new
project directory" as a signal to double-check, not silently proceed (the
importer script warns rather than silently creating new project dirs).

## Sensitive content in imported transcripts

Personal Cursor chat history can contain real financial/PII data (a real
example: a shop card number + PIN, extracted from a pasted image, appeared
verbatim in one imported transcript). This is fine to import for the user's
**own personal** projects (nothing leaves their machine, no publishing), but
never do this kind of bulk local-data copy for Gusto/company data without
checking `docs/coding-standards.md` / the org security instructions first —
the "stays 100% local, never transmitted" reasoning does not extend to
customer or company-confidential data.
