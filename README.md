# Dotfiles

Personal dotfiles repository for macOS development environment.

## Tech Stack & Frameworks

- **Shell**: ZSH with Oh-My-ZSH framework
- **Theme**: Dynamic theme switching:
  - **Powerlevel10k**: Default theme for regular terminal usage (rich, feature-full prompt)
  - **robbyrussell**: Automatically activated for Cursor AI command execution (clean, simple output)
- **ZSH Plugins**: 
  - git
  - zsh-syntax-highlighting
  - zsh-autosuggestions
  - docker
  - docker-compose
- **Runtime Management**: mise (replacing nvm, rbenv, etc.)
- **Package Management**: yarn (auto-installed with new Node versions)
- **Keyboard Customization**: Karabiner-Elements with goku (.edn compilation)

## Recent Updates

### Dynamic Theme Switching (2024)
- **Feature**: Automatic theme switching based on execution context
- **Detection**: Uses `CURSOR_TRACE_ID` environment variable to detect AI command execution
- **Behavior**:
  - Cursor AI commands: robbyrussell theme + `PAGER=cat` for non-interactive output
  - Regular terminals: Powerlevel10k theme with full features
- **Manual Control**:
  - `use_p10k` - Force Powerlevel10k theme
  - `use_robbyrussell` - Force robbyrussell theme
  - `theme_auto` - Return to automatic detection
  - `theme_status` - Check current theme settings
- **Implementation**: Modified `~/.zshrc` with context detection logic

## Scripts

- `./scripts/create_symlinks.sh` - Main setup script to create dotfile symlinks
- `./scripts/add_to_dotfiles.sh` - Add individual files/directories to dotfiles management
- `./scripts/scan_config.sh` - Interactive bulk management of ~/.config files
- `./scripts/keyboard_repeat_rate.sh` - Set macOS keyboard repeat settings
- `./scripts/gh_query.sh` - Query GitHub API for pull requests

## Setup

```bash
# Clone the repository
git clone git@github.com:jlee1201/dotfiles.git ~/dotfiles

# Run the setup script
cd ~/dotfiles
./scripts/create_symlinks.sh
```

## Adding New Dotfiles

```bash
# Add a single file or directory
./scripts/add_to_dotfiles.sh ~/path/to/file

# Bulk scan ~/.config
./scripts/scan_config.sh
```

See [CLAUDE.md](CLAUDE.md) for detailed documentation and troubleshooting notes. 