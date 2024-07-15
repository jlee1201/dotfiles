#!/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

# symlinked nested
ln -sf "$DIR"/.config/karabiner.edn ~/.config/karabiner.edn
ln -sfn "$DIR"/.hammerspoon ~/.hammerspoon
ln -sf "$DIR"/.ssh/config ~/.ssh/config
ln -sfn "$DIR"/.zfunc ~/.zfunc
ln -sf "$DIR"/nvm/default-packages "$NVM_DIR"/default-packages

# symlinked files
ln -sf "$DIR"/.gitconfig ~/.gitconfig
ln -sf "$DIR"/.gitignore ~/.gitignore
ln -sf "$DIR"/.p10k.zsh ~/.p10k.zsh
ln -sf "$DIR"/.profile ~/.profile
ln -sf "$DIR"/.profile ~/.bash_profile
ln -sf "$DIR"/.profile ~/.zprofile
ln -sf "$DIR"/.ruby-version ~/.ruby-version
ln -sf "$DIR"/.zshrc ~/.zshrc
