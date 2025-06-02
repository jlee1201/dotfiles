#!/usr/bin/env bash
# scan_config.sh - Script to scan ~/.config, identify new files, and update symlinks

# Get the dotfiles directory
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"
CONFIG_DIR="$HOME/.config"
DOTFILES_CONFIG_DIR="$DOTFILES_DIR/home/.config"
SYMLINKS_SCRIPT="$DOTFILES_DIR/scripts/create_symlinks.sh"

# Create .config directory in dotfiles home if it doesn't exist
mkdir -p "$DOTFILES_CONFIG_DIR"

# Function to check if a file is already symlinked to our dotfiles repo
is_symlinked_to_dotfiles() {
  local file="$1"
  local rel_path="${file#$CONFIG_DIR/}"
  local target_path="$DOTFILES_CONFIG_DIR/$rel_path"
  
  # Check if the file is a symlink pointing to our dotfiles repo
  if [[ -L "$file" && "$(readlink "$file")" == "$target_path" ]]; then
    return 0  # True, it's already symlinked to dotfiles
  fi
  
  return 1  # False, not symlinked to dotfiles
}

# Function to check if a symlink command exists in create_symlinks.sh
has_symlink_command() {
  local rel_path="$1"
  
  # Check if there's a symlink command in create_symlinks.sh for this file
  if grep -q "ln -sf.*\.config/$rel_path" "$SYMLINKS_SCRIPT"; then
    return 0  # True, there's a symlink command
  fi
  
  return 1  # False, no symlink command
}

# Function to add a symlink command to create_symlinks.sh
add_symlink_command() {
  local rel_path="$1"
  local target_dir="$(dirname "$DOTFILES_CONFIG_DIR/$rel_path")"
  
  # Create target directory if it doesn't exist
  mkdir -p "$target_dir"
  
  # Add symlink command to create_symlinks.sh if not already there
  if ! has_symlink_command "$rel_path"; then
    # Determine where to insert the new command
    local insert_line=$(grep -n "# Add more .config files as needed here" "$SYMLINKS_SCRIPT" | tail -1 | cut -d: -f1)
    
    # Create the new symlink command
    local cmd="ln -sf \"\$HOME_DIR/.config/$rel_path\" ~/.config/$rel_path"
    
    # Insert the command on a new line after the determined line
    sed -i.bak "${insert_line}a\\
$cmd" "$SYMLINKS_SCRIPT"
    
    rm -f "${SYMLINKS_SCRIPT}.bak"
    echo "Added symlink command for ~/.config/$rel_path"
  fi
}

# Function to remove a symlink command from create_symlinks.sh
remove_symlink_command() {
  local rel_path="$1"
  
  # Use grep to find the line with the symlink command for this path
  local line_number=$(grep -n "ln -sf.*\.config/$rel_path" "$SYMLINKS_SCRIPT" | cut -d: -f1)
  
  if [[ -n "$line_number" ]]; then
    # Delete the line
    sed -i.bak "${line_number}d" "$SYMLINKS_SCRIPT"
    rm -f "${SYMLINKS_SCRIPT}.bak"
    echo "Removed symlink command for ~/.config/$rel_path"
  fi
}

# Main function to scan and process config files/directories
scan_config() {
  echo "Scanning ~/.config directory for files and directories..."
  
  # Use find with dot_clean to ensure we handle dot files correctly
  find -L "$CONFIG_DIR" -mindepth 1 -maxdepth 1 | sort | while read -r path; do
    local rel_path="${path#$CONFIG_DIR/}"
    local is_symlinked=false
    local is_directory=false
    
    # Check if it's a directory
    if [[ -d "$path" && ! -L "$path" ]]; then
      is_directory=true
      echo "Processing directory: ~/.config/$rel_path"
    else
      echo "Processing file: ~/.config/$rel_path"
    fi
    
    # Skip certain directories that should not be symlinked
    if [[ "$rel_path" == ".git" || "$rel_path" == "node_modules" ]]; then
      echo "Skipping special directory: $rel_path"
      continue
    fi
    
    # Check if already symlinked to our dotfiles repo
    if is_symlinked_to_dotfiles "$path"; then
      is_symlinked=true
      echo "Currently symlinked to dotfiles repo: ~/.config/$rel_path"
    fi
    
    # Ask user if they want this file/directory in dotfiles
    echo "Should ~/.config/$rel_path be hosted in dotfiles? (y/n)"
    read -r answer </dev/tty
    
    if [[ "$answer" =~ ^[Yy] ]]; then
      # User wants file/directory in dotfiles
      
      if $is_symlinked; then
        # Already properly symlinked, do nothing
        echo "Already correctly symlinked, no action needed."
      else
        # Not symlinked to dotfiles repo yet
        echo "Adding to dotfiles repo..."
        
        # Make sure the target directory exists
        mkdir -p "$(dirname "$DOTFILES_CONFIG_DIR/$rel_path")"
        
        # If the item is already a symlink but not to our repo, resolve it first
        if [[ -L "$path" ]]; then
          local real_path=$(readlink -f "$path")
          # Remove the symlink
          rm "$path"
          # Copy the real content
          if [[ -d "$real_path" ]]; then
            cp -r "$real_path" "$DOTFILES_CONFIG_DIR/$rel_path"
          else
            cp "$real_path" "$DOTFILES_CONFIG_DIR/$rel_path"
          fi
        else
          # Regular file or directory, copy it
          if $is_directory; then
            # Copy directory contents
            mkdir -p "$DOTFILES_CONFIG_DIR/$rel_path"
            cp -r "$path/"* "$DOTFILES_CONFIG_DIR/$rel_path/" 2>/dev/null || true
            cp -r "$path/".[!.]* "$DOTFILES_CONFIG_DIR/$rel_path/" 2>/dev/null || true
          else
            # Copy file
            cp "$path" "$DOTFILES_CONFIG_DIR/$rel_path"
          fi
        fi
        
        # Add symlink command to script
        add_symlink_command "$rel_path"
        
        # Create the symlink (replacing the original file/directory)
        rm -rf "$path"
        ln -sf "$DOTFILES_CONFIG_DIR/$rel_path" "$path"
        echo "Created symlink for ~/.config/$rel_path"
      fi
    else
      # User does not want file/directory in dotfiles
      
      if $is_symlinked; then
        echo "Removing from dotfiles repo..."
        
        # Remove symlink and restore the original file/directory
        if [[ -e "$DOTFILES_CONFIG_DIR/$rel_path" ]]; then
          # Copy from dotfiles to local config
          if [[ -d "$DOTFILES_CONFIG_DIR/$rel_path" ]]; then
            # Remove symlink
            rm "$path"
            # Create directory
            mkdir -p "$path"
            # Copy contents
            cp -r "$DOTFILES_CONFIG_DIR/$rel_path/"* "$path/" 2>/dev/null || true
            cp -r "$DOTFILES_CONFIG_DIR/$rel_path/".[!.]* "$path/" 2>/dev/null || true
          else
            # File: remove symlink and copy the file
            rm "$path"
            cp "$DOTFILES_CONFIG_DIR/$rel_path" "$path"
          fi
        fi
        
        # Remove symlink command from script
        remove_symlink_command "$rel_path"
        
        echo "Removed symlink for ~/.config/$rel_path and restored local copy"
      else
        # Not symlinked, nothing to do
        echo "Not symlinked, no action needed."
      fi
    fi
    
    echo "--------"
  done
  
  echo "Scan complete. You may now run ./scripts/create_symlinks.sh to verify the symlinks."
}

# Run the main function
scan_config