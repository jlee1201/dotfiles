# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal dotfiles repository containing configuration files and setup scripts for a macOS development environment.

## Key Scripts and Commands

- **Setting up dotfiles**: `./scripts/create_symlinks.sh`
  - Creates symbolic links from the dotfiles in this repository to the home directory
  - This is the primary setup command for this repository

- **Setting keyboard repeat rate**: `./scripts/keyboard_repeat_rate.sh`
  - Sets macOS keyboard repeat settings (requires re-login to take effect)

- **GitHub API queries**: `./scripts/gh_query.sh [repo_owner] [repo_name]`
  - Queries GitHub API for open pull requests in the specified repository
  - Default: `ardiustech/mithrin`

## Repository Structure

- `/scripts/`: Utility scripts for environment setup
  - `create_symlinks.sh`: Creates symbolic links to home directory
  - `gh_query.sh`: GitHub API query script for pull requests 
  - `keyboard_repeat_rate.sh`: Sets keyboard repeat rate on macOS

- `/nvm/`: Node Version Manager configuration
  - `default-packages`: Lists packages (yarn) to install with new Node versions

- `/.config/`: Configuration files for various applications
  - `karabiner.edn`: Configuration for Karabiner-Elements keyboard customization

- Various dotfiles in the root directory referenced in the `create_symlinks.sh` script:
  - `.gitconfig`, `.zshrc`, `.profile`, `.p10k.zsh`, etc.

## Environment Configuration

### Shell Setup
- Uses ZSH with Oh-My-ZSH and Powerlevel10k theme
- Custom plugins: git, syntax highlighting, autosuggestions, docker
- Custom functions stored in `~/.zfunc/`

### Package Management
- Uses `mise` for runtime version management (replacing older tools like nvm, rbenv)
- Automatically installs yarn when installing a new Node version

### Keyboard Customization
- Extensive configuration for Karabiner-Elements
- Custom key layers, movement modes, and application-specific settings

## Working with this Repository

1. **Making Changes**: 
   - Edit files directly in this repository, not the symlinked versions
   - Changes should be committed to this repository

2. **Adding New Configuration**:
   - Add new files to the appropriate location in this repository
   - Update `create_symlinks.sh` to create the required symlinks

3. **Testing Changes**:
   - After making changes, run `./scripts/create_symlinks.sh` to update the symlinks
   - For Karabiner changes, you may need to reload Karabiner-Elements

4. **Security Note**:
   - Be careful with `gh_query.sh` as it contains a GitHub token
   - Consider moving sensitive tokens to a secure location

## Dependencies

- [Oh-My-ZSH](https://ohmyz.sh/)
- [Powerlevel10k](https://github.com/romkatv/powerlevel10k)
- [Karabiner-Elements](https://karabiner-elements.pqrs.org/)
- [mise](https://github.com/jdx/mise) (runtime version manager)