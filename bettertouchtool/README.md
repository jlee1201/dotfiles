# BetterTouchTool config

JSON snapshot of my BetterTouchTool config, kept under version control for portability and history.

## Why JSON, not the live data store?

BetterTouchTool's live config lives in `~/Library/Application Support/BetterTouchTool/` as SQLite databases (`btt_data_store.version_*`). That directory is not version-control friendly:

- Binary SQLite files produce useless diffs.
- WAL/SHM sidecars (`*-wal`, `*-shm`) churn constantly while BTT is running.
- The DB filename includes BTT's version number, so it changes on every BTT update.
- The directory contains the license file (`*.bttlicense`) and runtime logs.

JSON exports avoid all of that: text-diffable, version-stable, portable across machines and BTT versions.

## Restore on a new machine

1. Install BetterTouchTool.
2. Open BetterTouchTool's preferences/config window.
3. Open **Manage Presets** (menu bar: `BetterTouchTool → Manage Presets`, or via the preset selector in the config window).
4. Click **Import Preset** and select `btt-config.json` from this folder.
   - The file is named `.json` here for editor syntax highlighting and git tooling — BTT accepts it regardless of extension since it's plain JSON.
   - If BTT's import dialog filters by extension and won't show the file, rename to `btt-config.bttpreset` first or temporarily change the extension.
5. After import, set this preset as active (it will appear in the preset list).

## Refresh the snapshot after making changes

When you add/modify config and want to capture the new state in git:

1. Open BetterTouchTool → **Manage Presets**.
2. Select the active preset (likely "Default") and click **Export Preset**.
3. Save to `~/Downloads/Default.bttpreset` (the script's default input path).
4. Run the normalize script to strip noise fields and overwrite `btt-config.json`:
   ```bash
   cd ~/workspace/personal/dotfiles/bettertouchtool && ./normalize.sh
   ```
   (Or pass a different input path: `./normalize.sh /path/to/export.bttpreset`)
5. Review changes: `cd ~/workspace/personal/dotfiles && git diff bettertouchtool/btt-config.json`
6. Commit with a message describing what you changed (e.g. `btt: tweak snap area on portrait monitor`).

The `normalize.sh` script strips fields that change every BTT launch but aren't real config — see the script header for the full list. It also enforces consistent JSON formatting (via `jq`) so future diffs stay focused on actual changes.

### Multiple presets?

BTT supports multiple presets (e.g. "Default", "Work", a game-specific one). If you have more than one and want all of them tracked, export each separately and save as `btt-config-<presetname>.json`. The `Default` preset is the always-active baseline.

## What this snapshot currently captures

Inspecting `btt-config.json`:

- **`BTTGeneralSettings`** — ~180 general BTT preferences (mouse pressure thresholds, gesture sensitivity, notch bar settings, touch bar settings, snap area defaults, drawing settings, etc.).
- **`BTTPresetSnapAreas`** — Custom snap areas (window-snap zones) for your displays.
- **`BTTPresetContent`** — Per-app entries. Currently the `BTTTriggers` arrays are empty — meaning the active "Default" preset does not have keyboard/trackpad/mouse triggers configured. If you later add triggers (or have other presets), they will show up here on the next export.

## Noise fields stripped by `normalize.sh`

These fields change every BTT launch but aren't meaningful config. The script removes them before writing `btt-config.json`:

- `BTTNumberOfStarts` — increments every BTT launch
- `BTTSavedMousePosition` — last known mouse coords
- `BTTLastClamshellState` — lid state at export time
- `BTTDidRegisterForUpdateStats` — BTT version string
- `BTTSelectedKeyboardTabIndex` — which UI tab was last open

If you find other noisy fields in future diffs (i.e. they change without any meaningful config change on your part), add them to the `del(...)` chain in `normalize.sh`.

## License recovery

The license file (`bettertouchtool.bttlicense`) is **NOT** in this repo (this repo is public, and the license is a credential).

**Primary recovery path — 1Password:**

- Vault: `Private`
- Item title: `BetterTouchTool License`
- Category: Software License
- Both `.bttlicense` files (`bettertouchtool.bttlicense` and `urlimported.bttlicense`) are attached as files
- Structured fields include: registered email, license type, order number, transaction id, purchase timestamp, recovery URL

**To restore the license on a new machine:**

1. Open 1Password, navigate to `Private` → `BetterTouchTool License`
2. Download both attached files
3. Move them to `~/Library/Application Support/BetterTouchTool/` (create the directory if BTT hasn't run yet)
4. Restart BTT — license should activate automatically

**Fallback recovery path — BTT support:**

If the 1Password item is unavailable for any reason:

1. Visit https://folivora.ai/lostlicense
2. Enter the registered email (also stored in the 1Password item, or check your purchase email)
3. BTT will email a re-activation link

## What's NOT tracked here

These live in `~/Library/Application Support/BetterTouchTool/` and intentionally stay there:

- `btt_data_store.version_*` — the live SQLite config (BTT reads/writes this directly)
- `btt_data_store.version_*-wal` / `-shm` — SQLite sidecars
- `Backups/` — BTT's own automatic backup snapshots (keep enabled in BTT settings as a separate disaster-recovery layer)
- `Logs/` — runtime logs
- `bettertouchtool.bttlicense` / `urlimported.bttlicense` — license files (in 1Password instead, see above)
- `Files/` — supporting files referenced by triggers (script files, images, etc.) — TODO: revisit if specific triggers need files committed

## Optional: further automation

If manual re-export-then-`./normalize.sh` becomes a chore:

- **Pre-commit hook** in this repo that auto-runs `normalize.sh` if a fresh `~/Downloads/Default.bttpreset` exists.
- **launchd job** that re-exports daily/weekly. This requires automating BTT's export step, which is the hard part — BetterTouchTool's CLI/AppleScript interface for "export preset" is limited. Manual export remains the most reliable path until BTT exposes a CLI.

Defer until the manual flow becomes painful.
