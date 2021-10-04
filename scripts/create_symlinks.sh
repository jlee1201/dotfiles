#!/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

ln -sf "$DIR"/.zshrc ~/.zshrc
ln -sf "$DIR"/.rvmrc ~/.rvmrc
ln -sf "$DIR"/.p10k.zsh ~/.p10k.zsh
ln -sf "$DIR"/.gitconfig ~/.gitconfig
ln -sfn "$DIR"/.zfunc ~/.zfunc
ln -sf "$DIR"/.ssh/config ~/.ssh/config
ln -sf "$DIR"/.config/karabiner.edn ~/.config/karabiner.edn
ln -sfn "$DIR"/.hammerspoon ~/.hammerspoon
