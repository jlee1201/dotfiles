#!/usr/bin/env bash
# Symlink dotfiles from this repo's home/ into ~/. Idempotent, safe, self-healing.
#
# Re-running is safe:
#  - uses `ln -sfn` so an existing symlink-to-directory is replaced in place. The old
#    `ln -sf` dereferenced it and nested a stray self-loop inside instead, e.g.
#    ~/.config/mise/mise -> .../home/.config/mise;
#  - removes any such stray self-loop it finds (heals prior damage);
#  - NEVER clobbers a real file or non-empty real directory at the destination -- it
#    warns and leaves your data alone (e.g. a live ~/.config/gh with auth in hosts.yml).
set -uo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"
HOME_DIR="$DIR/home"

# link <repo-relative-path> [dest]   (dest defaults to ~/<path>)
link() {
  local src="$HOME_DIR/$1"
  local dest="${2:-$HOME/$1}"
  if [ ! -e "$src" ]; then
    echo "skip (not in repo): $1" >&2
    return 0
  fi
  mkdir -p "$(dirname "$dest")"

  # Heal a stray self-loop the old buggy script could nest: <dest>/<basename> -> src
  local nested="$dest/$(basename "$dest")"
  if [ -L "$nested" ] && [ "$(readlink "$nested")" = "$src" ]; then
    rm -f "$nested" && echo "healed stray loop: $nested" >&2
  fi

  # Already the correct link? Nothing to do.
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    return 0
  fi
  # Replace a wrong/old symlink or an EMPTY real dir; never destroy real data.
  if [ -L "$dest" ]; then
    rm -f "$dest"
  elif [ -d "$dest" ] && [ -z "$(ls -A "$dest" 2>/dev/null)" ]; then
    rmdir "$dest"
  elif [ -e "$dest" ]; then
    echo "WARN: $dest holds real data (not our symlink); leaving it untouched" >&2
    return 0
  fi
  ln -sfn "$src" "$dest"
}

# ~/.config (files + directories)
link .config/karabiner.edn
link .config/mise
link .config/git
link .config/gh
link .config/claude-code-launcher

# nested directories / files
link .hammerspoon
mkdir -p ~/.ssh && chmod 700 ~/.ssh
link .ssh/config
link .zfunc

# oldmac (old-Mac coordination): cross-agent CLI + discovery pointers
link .cursor/skills/oldmac-coord/SKILL.md
link .codex/AGENTS.md
link .local/bin/oldmac

# home dotfiles
link .claude
link .claude.json
link .gitconfig
link .gitignore
link .p10k.zsh
link .profile
link .profile "$HOME/.bash_profile"
link .profile "$HOME/.zprofile"
link .ruby-version
link .zshrc
