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

### Enhanced Scrolling System (SOLVED - 2025-01-02)

**Goal**: Enable `fn + s + trackpad drag` for smooth scrolling with modifier key support (cmd+scroll for zoom, etc.).

**Final Solution**: 
- ✅ `fn + s + trackpad drag` = smooth, responsive scrolling
- ✅ `cmd + fn + s + trackpad drag` = zoom in/out in Figma and design apps
- ✅ `ctrl + fn + s + trackpad drag` = zoom in browsers and other apps
- ✅ All modifier combinations work properly

**Key Architecture Decision**: 
- **Abandoned**: Karabiner-Elements `mouse_motion_to_scroll` approach (unreliable, no modifier support)
- **Adopted**: Hammerspoon-based middle mouse button emulation with modifier detection

**What Works**:
- Karabiner maps `fn + s` to middle mouse button (button 2)
- Hammerspoon intercepts middle mouse button drag events
- Hammerspoon detects modifier keys and passes them to scroll events
- Applications receive proper scroll events with modifiers and respond correctly

**Technical Implementation**:
- Karabiner config: `[:##s :button3]` in movement_mode (maps to middle mouse button)
- Hammerspoon: Event taps on `otherMouseDown`, `otherMouseUp`, `otherMouseDragged`
- Modifier detection: Both `eventFlags` and `checkKeyboardModifiers()` for reliability
- Scroll generation: `newScrollEvent({dx, dy}, modifiers, "pixel")`

**Critical Dependencies**:
- Hammerspoon must be running for Karabiner's `multitouch_extension_finger_count_total` to work
- Without Hammerspoon: trackpad finger count detection fails, movement_mode doesn't activate

**Failed Approaches**:
1. **Karabiner mouse_motion_to_scroll** - Unreliable, couldn't detect conditions properly, no modifier support
2. **Various momentum implementations**:
   - Momentum on mouse button release (wrong trigger - should be finger lift)
   - Velocity tracking during drag (made scrolling choppy)
   - Timer-based gesture end detection (never triggered properly)
   - Multiple decay algorithms (none felt natural)

**Key Learnings**:
- Karabiner-Elements `mouse_motion_to_scroll` is fundamentally limited for complex scenarios
- Hammerspoon provides much better control over event generation and modifier handling
- Momentum scrolling detection requires identifying "finger lifted from trackpad" while maintaining button press
- Simple, responsive immediate scrolling often better than complex momentum systems
- Modifier key detection needs dual approach (event flags + system modifiers) for reliability

**System Configuration**:
- macOS with SIP enabled
- Hammerspoon has Accessibility and Input Monitoring permissions
- Karabiner-Elements with goku for .edn compilation
- Interdependent: Hammerspoon + Karabiner both required

**Files Modified**:
- `home/.config/karabiner.edn` - Removed mouse_motion_to_scroll, kept movement_mode
- `home/.hammerspoon/init.lua` - Complete middle mouse button scroll implementation