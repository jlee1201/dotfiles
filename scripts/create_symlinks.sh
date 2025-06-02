#!/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"
HOME_DIR="$DIR/home"

# Create .config directory if it doesn't exist
mkdir -p ~/.config

# Individual .config files and directories
ln -sf "$HOME_DIR/.config/karabiner.edn" ~/.config/karabiner.edn
# Add more .config files as needed here
ln -sf "$HOME_DIR/.config/mise" ~/.config/mise
ln -sf "$HOME_DIR/.config/git" ~/.config/git
ln -sf "$HOME_DIR/.config/gh" ~/.config/gh
ln -sf "$HOME_DIR/.config/claude-code-launcher" ~/.config/claude-code-launcher
# symlinked nested directories 
ln -sfn "$HOME_DIR/.hammerspoon" ~/.hammerspoon
ln -sf "$HOME_DIR/.ssh/config" ~/.ssh/config
ln -sfn "$HOME_DIR/.zfunc" ~/.zfunc

# symlinked files
ln -sf "$HOME_DIR/.gitconfig" ~/.gitconfig
ln -sf "$HOME_DIR/.gitignore" ~/.gitignore
ln -sf "$HOME_DIR/.p10k.zsh" ~/.p10k.zsh
ln -sf "$HOME_DIR/.profile" ~/.profile
ln -sf "$HOME_DIR/.profile" ~/.bash_profile
ln -sf "$HOME_DIR/.profile" ~/.zprofile
ln -sf "$HOME_DIR/.ruby-version" ~/.ruby-version
ln -sf "$HOME_DIR/.zshrc" ~/.zshrc
