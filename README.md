# Dotfiles

Personal dotfiles repository for macOS development environment.

## Quick Overview

**Main Tools**: ZSH + Oh-My-ZSH, Karabiner-Elements, Hammerspoon, mise runtime management

**Key Features**:
- Dynamic shell theme switching (Powerlevel10k ↔ robbyrussell based on context)
- Enhanced scrolling system (`fn + s + trackpad` with modifier support)
- Automated dotfiles management with symlink scripts

## Quick Start

```bash
# Clone the repository
git clone git@github.com:jlee1201/dotfiles.git ~/dotfiles

# Run the setup script
cd ~/dotfiles
./scripts/create_symlinks.sh
```

## Documentation

**📋 Complete Documentation**: [.cursor/README.md](.cursor/README.md)

**Quick Links**:
- **[Tech Stack & Dependencies](.cursor/repository-overview.mdc)** - Full list of tools and frameworks
- **[Scripts & Commands](.cursor/scripts-and-commands.mdc)** - Available scripts and how to use them
- **[Workflow Guide](.cursor/workflow-guide.mdc)** - How to add dotfiles, make changes, and test
- **[Troubleshooting](.cursor/troubleshooting.mdc)** - Solutions to common issues (including scrolling system)
- **[Architecture Decisions](.cursor/architecture-decisions.mdc)** - Technical decisions and learnings

## Adding New Dotfiles

```bash
# Add a single file or directory
./scripts/add_to_dotfiles.sh ~/path/to/file

# Bulk scan ~/.config
./scripts/scan_config.sh
```

*For detailed usage and all available scripts, see [Scripts & Commands](.cursor/scripts-and-commands.mdc)* 