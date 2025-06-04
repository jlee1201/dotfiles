#!/usr/bin/env bash
# add_to_dotfiles.sh - Script to add a specific file or directory to dotfiles management

# Usage: ./scripts/add_to_dotfiles.sh ~/filename or ./scripts/add_to_dotfiles.sh ~/dirname

set -e  # Exit on any error

# Get the dotfiles directory
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"
HOME_DIR="$DOTFILES_DIR/home"
SYMLINKS_SCRIPT="$DOTFILES_DIR/scripts/create_symlinks.sh"

# Check if argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 ~/<filename|dirname>"
    echo "Example: $0 ~/.vimrc"
    echo "Example: $0 ~/.local"
    exit 1
fi

# Get the argument and expand the tilde
ARG="$1"
if [[ "$ARG" == "~/"* ]]; then
    # Handle literal tilde format: ~/.claude.json
    # Remove the ~/ prefix and prepend HOME
    TARGET_PATH="$HOME/${ARG:2}"
elif [[ "$ARG" == "$HOME/"* ]]; then
    # Handle already expanded path: /Users/john.lee/.claude.json
    TARGET_PATH="$ARG"
else
    echo "Error: Argument must be either ~/filename or a path in your home directory (got: $ARG)"
    exit 1
fi

# Check if the target exists
if [ ! -e "$TARGET_PATH" ]; then
    echo "Error: $TARGET_PATH does not exist"
    exit 1
fi

# Get relative path from home directory
REL_PATH="${TARGET_PATH#$HOME/}"
DOTFILES_TARGET_PATH="$HOME_DIR/$REL_PATH"

echo "Processing: $TARGET_PATH"
echo "Target in dotfiles: $DOTFILES_TARGET_PATH"

# Function to check if a symlink command exists in create_symlinks.sh
has_symlink_command() {
    local rel_path="$1"
    
    # Escape special characters for grep
    local escaped_path=$(printf '%s\n' "$rel_path" | sed 's/[[\.*^$()+?{|]/\\&/g')
    
    # Check if there's a symlink command in create_symlinks.sh for this file
    if grep -q "ln -sf.*\"$escaped_path\"" "$SYMLINKS_SCRIPT"; then
        return 0  # True, there's a symlink command
    fi
    
    return 1  # False, no symlink command
}

# Function to add a symlink command to create_symlinks.sh
add_symlink_command() {
    local rel_path="$1"
    
    # Add symlink command to create_symlinks.sh if not already there
    if ! has_symlink_command "$rel_path"; then
        # Create the new symlink command
        local cmd="ln -sf \"\$HOME_DIR/$rel_path\" ~/$rel_path"
        
        # Determine the right section to add to
        if [[ "$rel_path" == .config/* ]]; then
            # Add to .config section
            local insert_line=$(grep -n "# Add more .config files as needed here" "$SYMLINKS_SCRIPT" | tail -1 | cut -d: -f1)
            
            if [ -n "$insert_line" ]; then
                # Insert after the comment line
                head -n "$insert_line" "$SYMLINKS_SCRIPT" > "${SYMLINKS_SCRIPT}.tmp"
                echo "$cmd" >> "${SYMLINKS_SCRIPT}.tmp"
                tail -n +"$((insert_line + 1))" "$SYMLINKS_SCRIPT" >> "${SYMLINKS_SCRIPT}.tmp"
                mv "${SYMLINKS_SCRIPT}.tmp" "$SYMLINKS_SCRIPT"
            else
                # If comment not found, add after the last .config line
                insert_line=$(grep -n "ln -sf.*\.config" "$SYMLINKS_SCRIPT" | tail -1 | cut -d: -f1)
                if [ -n "$insert_line" ]; then
                    head -n "$insert_line" "$SYMLINKS_SCRIPT" > "${SYMLINKS_SCRIPT}.tmp"
                    echo "$cmd" >> "${SYMLINKS_SCRIPT}.tmp"
                    tail -n +"$((insert_line + 1))" "$SYMLINKS_SCRIPT" >> "${SYMLINKS_SCRIPT}.tmp"
                    mv "${SYMLINKS_SCRIPT}.tmp" "$SYMLINKS_SCRIPT"
                else
                    # Add to end of file
                    echo "$cmd" >> "$SYMLINKS_SCRIPT"
                fi
            fi
        else
            # Add to appropriate section (files vs directories)
            if [ -d "$TARGET_PATH" ]; then
                # Directory - add to symlinked nested directories section
                local insert_line=$(grep -n "# symlinked nested directories" "$SYMLINKS_SCRIPT" | tail -1 | cut -d: -f1)
                if [ -n "$insert_line" ]; then
                    # Use ln -sfn for directories
                    cmd="ln -sfn \"\$HOME_DIR/$rel_path\" ~/$rel_path"
                    head -n "$insert_line" "$SYMLINKS_SCRIPT" > "${SYMLINKS_SCRIPT}.tmp"
                    echo "$cmd" >> "${SYMLINKS_SCRIPT}.tmp"
                    tail -n +"$((insert_line + 1))" "$SYMLINKS_SCRIPT" >> "${SYMLINKS_SCRIPT}.tmp"
                    mv "${SYMLINKS_SCRIPT}.tmp" "$SYMLINKS_SCRIPT"
                else
                    # Add to end of file
                    echo "$cmd" >> "$SYMLINKS_SCRIPT"
                fi
            else
                # File - add to symlinked files section
                local insert_line=$(grep -n "# symlinked files" "$SYMLINKS_SCRIPT" | tail -1 | cut -d: -f1)
                if [ -n "$insert_line" ]; then
                    head -n "$insert_line" "$SYMLINKS_SCRIPT" > "${SYMLINKS_SCRIPT}.tmp"
                    echo "$cmd" >> "${SYMLINKS_SCRIPT}.tmp"
                    tail -n +"$((insert_line + 1))" "$SYMLINKS_SCRIPT" >> "${SYMLINKS_SCRIPT}.tmp"
                    mv "${SYMLINKS_SCRIPT}.tmp" "$SYMLINKS_SCRIPT"
                else
                    # Add to end of file
                    echo "$cmd" >> "$SYMLINKS_SCRIPT"
                fi
            fi
        fi
        
        echo "Added symlink command for ~/$rel_path"
        return 0
    else
        echo "Symlink command already exists for ~/$rel_path"
        return 1
    fi
}

# Check if target is already a symlink pointing to dotfiles
if [ -L "$TARGET_PATH" ]; then
    LINK_TARGET=$(readlink "$TARGET_PATH")
    if [[ "$LINK_TARGET" == "$DOTFILES_TARGET_PATH" ]] || [[ "$LINK_TARGET" == "$HOME_DIR/$REL_PATH" ]]; then
        echo "✓ $TARGET_PATH is already a symlink pointing to dotfiles repository"
        echo "Nothing to do."
        exit 0
    else
        echo "⚠ $TARGET_PATH is a symlink but points to: $LINK_TARGET"
        echo "This will be replaced with a symlink to dotfiles repository"
    fi
fi

echo "Moving $TARGET_PATH to dotfiles repository..."

# Create target directory structure
TARGET_DIR=$(dirname "$DOTFILES_TARGET_PATH")
mkdir -p "$TARGET_DIR"

# Move the file/directory to dotfiles
if [ -d "$TARGET_PATH" ] && [ ! -L "$TARGET_PATH" ]; then
    # It's a directory - move it
    mv "$TARGET_PATH" "$DOTFILES_TARGET_PATH"
elif [ -f "$TARGET_PATH" ] && [ ! -L "$TARGET_PATH" ]; then
    # It's a file - move it
    mv "$TARGET_PATH" "$DOTFILES_TARGET_PATH"
elif [ -L "$TARGET_PATH" ]; then
    # It's a symlink - resolve and copy the target, then remove the symlink
    REAL_PATH=$(readlink -f "$TARGET_PATH")
    rm "$TARGET_PATH"
    if [ -d "$REAL_PATH" ]; then
        cp -r "$REAL_PATH" "$DOTFILES_TARGET_PATH"
    else
        cp "$REAL_PATH" "$DOTFILES_TARGET_PATH"
    fi
else
    echo "Error: Unable to determine type of $TARGET_PATH"
    exit 1
fi

echo "✓ Moved to: $DOTFILES_TARGET_PATH"

# Add symlink command to create_symlinks.sh
add_symlink_command "$REL_PATH"

# Run create_symlinks.sh to create the symlink
echo "Running create_symlinks.sh to create symlink..."
cd "$DOTFILES_DIR"
bash "$SYMLINKS_SCRIPT"

# Verify the symlink was created successfully
if [ -L "$TARGET_PATH" ]; then
    ACTUAL_TARGET=$(readlink "$TARGET_PATH")
    if [[ "$ACTUAL_TARGET" == "$DOTFILES_TARGET_PATH" ]] || [[ "$ACTUAL_TARGET" == "$HOME_DIR/$REL_PATH" ]]; then
        echo "✓ Symlink created successfully: $TARGET_PATH -> $ACTUAL_TARGET"
    else
        echo "⚠ Symlink created but points to unexpected target: $ACTUAL_TARGET"
        exit 1
    fi
else
    echo "✗ Failed to create symlink at $TARGET_PATH"
    exit 1
fi

echo "✓ Successfully added $TARGET_PATH to dotfiles management" 