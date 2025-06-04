# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal dotfiles repository containing configuration files and setup scripts for a macOS development environment.

## Key Scripts and Commands

- **Setting up dotfiles**: `./scripts/create_symlinks.sh`
  - Creates symbolic links from the dotfiles in this repository to the home directory
  - This is the primary setup command for this repository

- **Adding individual files/directories to dotfiles**: `./scripts/add_to_dotfiles.sh ~/filename`
  - Adds a specific file or directory from the home directory to dotfiles management
  - Automatically moves the file/directory to the dotfiles repository and creates a symlink
  - Handles files, directories, and existing symlinks properly
  - Updates the `create_symlinks.sh` script with the new symlink entry
  - Example: `./scripts/add_to_dotfiles.sh ~/.vimrc` or `./scripts/add_to_dotfiles.sh ~/.local`

- **Scanning config directory**: `./scripts/scan_config.sh`
  - Interactive script that scans ~/.config directory for files/directories
  - Prompts user to add each item to dotfiles management
  - Useful for bulk configuration management

- **Setting keyboard repeat rate**: `./scripts/keyboard_repeat_rate.sh`
  - Sets macOS keyboard repeat settings (requires re-login to take effect)

- **GitHub API queries**: `./scripts/gh_query.sh [repo_owner] [repo_name]`
  - Queries GitHub API for open pull requests in the specified repository
  - Default: `ardiustech/mithrin`

## Repository Structure

- `/scripts/`: Utility scripts for environment setup
  - `create_symlinks.sh`: Creates symbolic links to home directory
  - `add_to_dotfiles.sh`: Adds individual files/directories to dotfiles management
  - `scan_config.sh`: Interactive script for scanning and managing ~/.config files
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
- **Important Note**: Any change to `karabiner.edn` requires running the goku command line to update the `karabiner.json` file which is what Karabiner-Elements ultimately reads

## Working with this Repository

1. **Making Changes**: 
   - Edit files directly in this repository, not the symlinked versions
   - Changes should be committed to this repository

2. **Adding New Configuration**:
   - **Easy way**: Use `./scripts/add_to_dotfiles.sh ~/filename` to automatically add a file or directory to dotfiles management
   - **Manual way**: Add new files to the appropriate location in this repository and update `create_symlinks.sh` to create the required symlinks
   - For bulk ~/.config management, use `./scripts/scan_config.sh` for interactive processing

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

## Troubleshooting Notes

### Ctrl+Scroll Zoom with Mouse Motion (UNSOLVED - 2025-06-03)

**Goal**: Enable `fn + ctrl + s + mouse drag` to produce ctrl+scroll zoom behavior (like trackpad two-finger scroll with ctrl held).

**Current Status**: 
- ✅ `fn + s + mouse drag` = regular scrolling (works perfectly)
- ❌ `fn + ctrl + s + mouse drag` = should zoom but only produces regular scroll

**What Works**:
- Karabiner successfully detects the key combinations and sets appropriate variables
- Hammerspoon correctly detects the ctrl modifier in event flags (`{ctrl = true}`)
- Regular mouse-drag-to-scroll functionality works via middle mouse button emulation
- All system permissions are properly configured (Accessibility, Input Monitoring)

**Technical Details**:
- Karabiner config: `[:!Ts ["ctrl_mouse_scroll_mode" 1] :movement_mode]` in modifier remapping
- Hammerspoon detects modifiers: Event flags show `{ctrl = true}`, system modifiers often empty
- Applications correctly respond to real trackpad ctrl+scroll for zoom

**Failed Approaches Tried**:
1. **Karabiner mouse_motion_to_scroll with modifiers** - Karabiner cannot inject modifiers into generated scroll events
2. **Hammerspoon newScrollEvent with various modifier formats**:
   - `{"ctrl"}`, `{"^"}`, `{"control"}`, `{"⌃"}`
   - `{ctrl=true}`, `{control=true}`
   - Using event flags directly, system modifiers
   - Both "pixel" and "line" units
3. **Hammerspoon scrollWheel with modifiers** - Same issue as newScrollEvent
4. **Manual ctrl key down/up sequences** - Fundamentally incorrect approach
5. **Setting flags manually with setFlags()** - No effect
6. **Middle mouse button emulation with ctrl** - Ctrl modifier not passed through to scroll events

**Key Insight**: Applications can distinguish between synthetic scroll events and real trackpad events. Real ctrl+trackpad scroll produces zoom, but synthetic ctrl+scroll events (even with proper modifiers) are treated as regular scroll.

**System Configuration**:
- macOS with SIP enabled
- Hammerspoon has Accessibility and Input Monitoring permissions
- Karabiner-Elements with goku for .edn compilation
- Working Hammerspoon middle-mouse-button scroll implementation

**Possible Root Causes**:
- macOS security restrictions on synthetic events with modifiers
- Different event pathway for trackpad vs synthetic scroll events
- Application-specific handling that ignores synthetic ctrl+scroll
- Fundamental limitation in Hammerspoon's scroll event generation

**Files Modified**:
- `home/.config/karabiner.edn` - Various mouse_motion_to_scroll configurations
- `home/.hammerspoon/init.lua` - Extensive scroll event generation attempts

**Future Investigation Ideas**:
- Try different automation tools (AppleScript, other event injectors)
- Investigate if any apps respond to synthetic ctrl+scroll
- Research macOS scroll event internals and required attributes
- Consider if other modifier combinations work (cmd+scroll, option+scroll)