#!/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

# Create .config directory if it doesn't exist
mkdir -p ~/.config

# Individual .config files and directories
ln -sf "$DIR"/.config/karabiner.edn ~/.config/karabiner.edn
# Add more .config files as needed here

# symlinked nested directories 
ln -sfn "$DIR"/.hammerspoon ~/.hammerspoon
ln -sf "$DIR"/.ssh/config ~/.ssh/config
ln -sfn "$DIR"/.zfunc ~/.zfunc

# symlinked files
ln -sf "$DIR"/.gitconfig ~/.gitconfig
ln -sf "$DIR"/.gitignore ~/.gitignore
ln -sf "$DIR"/.p10k.zsh ~/.p10k.zsh
ln -sf "$DIR"/.profile ~/.profile
ln -sf "$DIR"/.profile ~/.bash_profile
ln -sf "$DIR"/.profile ~/.zprofile
ln -sf "$DIR"/.ruby-version ~/.ruby-version
ln -sf "$DIR"/.zshrc ~/.zshrc
