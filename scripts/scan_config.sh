#!/usr/bin/env bash
# scan_config.sh - Script to scan ~/.config, identify new files, and update symlinks

# Get the dotfiles directory
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"
CONFIG_DIR="$HOME/.config"
DOTFILES_CONFIG_DIR="$DOTFILES_DIR/home/.config"
SYMLINKS_SCRIPT="$DOTFILES_DIR/scripts/create_symlinks.sh"

# Create .config directory in dotfiles home if it doesn't exist
mkdir -p "$DOTFILES_CONFIG_DIR"

# Function to check if a file is already symlinked
is_symlinked() {
  local file="$1"
  local rel_path="${file#$CONFIG_DIR/}"
  local target_path="$DOTFILES_CONFIG_DIR/$rel_path"
  
  # Check if the file is a symlink pointing to our dotfiles repo
  if [[ -L "$file" && "$(readlink "$file")" == "$target_path" ]]; then
    return 0  # True, it's already symlinked
  fi
  
  # Check if there's already a symlink command in create_symlinks.sh for this file
  if grep -q "ln -sf.*$rel_path" "$SYMLINKS_SCRIPT"; then
    return 0  # True, there's already a symlink command
  fi
  
  return 1  # False, not symlinked
}

# Function to add a symlink command to create_symlinks.sh
add_symlink_command() {
  local file="$1"
  local rel_path="${file#$CONFIG_DIR/}"
  local target_dir="$(dirname "$DOTFILES_CONFIG_DIR/$rel_path")"
  
  # Create target directory if it doesn't exist
  mkdir -p "$target_dir"
  
  # Add symlink command to create_symlinks.sh if not already there
  if ! grep -q "ln -sf.*$rel_path" "$SYMLINKS_SCRIPT"; then
    # Determine where to insert the new command - after the last .config related line
    local insert_line=$(grep -n ".config" "$SYMLINKS_SCRIPT" | tail -1 | cut -d: -f1)
    if [[ -z "$insert_line" ]]; then
      # If no .config lines, add after the "symlinked nested" comment
      insert_line=$(grep -n "symlinked nested" "$SYMLINKS_SCRIPT" | tail -1 | cut -d: -f1)
    fi
    
    # Create the new symlink command
    local cmd="ln -sf \"\$HOME_DIR/.config/$rel_path\" ~/.config/$rel_path"
    
    # Insert the command after the determined line
    sed -i.bak "${insert_line}a\\
$cmd" "$SYMLINKS_SCRIPT"
    
    rm -f "${SYMLINKS_SCRIPT}.bak"
    echo "Added symlink command for ~/.config/$rel_path"
  fi
}

# Main function to scan and process config files
scan_config() {
  echo "Scanning ~/.config directory for files not yet in dotfiles repo..."
  
  # Process each file in ~/.config (non-recursively first)
  find "$CONFIG_DIR" -maxdepth 1 -type f | while read -r file; do
    local rel_path="${file#$CONFIG_DIR/}"
    
    # Skip if file is already symlinked
    if is_symlinked "$file"; then
      echo "ALREADY SYMLINKED: ~/.config/$rel_path"
      continue
    fi
    
    # Ask user if they want to add this file to dotfiles
    echo "Add ~/.config/$rel_path to dotfiles? (y/n) "
    read -r answer </dev/tty
    
    if [[ "$answer" =~ ^[Yy] ]]; then
      # Copy the file to dotfiles
      cp "$file" "$DOTFILES_CONFIG_DIR/$rel_path"
      echo "Copied to $DOTFILES_CONFIG_DIR/$rel_path"
      
      # Add symlink command to create_symlinks.sh
      add_symlink_command "$file"
    fi
  done
  
  # Process subdirectories
  find "$CONFIG_DIR" -mindepth 1 -maxdepth 1 -type d | while read -r dir; do
    local rel_path="${dir#$CONFIG_DIR/}"
    
    # Skip certain directories that should not be symlinked
    if [[ "$rel_path" == ".git" || "$rel_path" == "node_modules" ]]; then
      continue
    fi
    
    # Ask user if they want to add this directory to dotfiles
    echo "Process directory ~/.config/$rel_path? (y/n/a) [y=yes, n=no, a=all files] "
    read -r answer </dev/tty
    
    if [[ "$answer" =~ ^[Yy] ]]; then
      # Create target directory in dotfiles
      mkdir -p "$DOTFILES_CONFIG_DIR/$rel_path"
      
      # Add symlink command to create_symlinks.sh if not already there
      if ! grep -q "ln -sf.*\.config/$rel_path" "$SYMLINKS_SCRIPT"; then
        local insert_line=$(grep -n "# Add more .config files as needed here" "$SYMLINKS_SCRIPT" | tail -1 | cut -d: -f1)
        local cmd="ln -sf \"\$HOME_DIR/.config/$rel_path\" ~/.config/$rel_path"
        
        sed -i.bak "${insert_line}i\\
$cmd" "$SYMLINKS_SCRIPT"
        
        rm -f "${SYMLINKS_SCRIPT}.bak"
        echo "Added symlink command for ~/.config/$rel_path directory"
      fi
      
    elif [[ "$answer" =~ ^[Aa] ]]; then
      # Copy all files in the directory
      mkdir -p "$DOTFILES_CONFIG_DIR/$rel_path"
      rsync -av --exclude=".git" --exclude="node_modules" "$dir/" "$DOTFILES_CONFIG_DIR/$rel_path/"
      echo "Copied all files from ~/.config/$rel_path to dotfiles"
      
      # Add symlink command to create_symlinks.sh if not already there
      if ! grep -q "ln -sf.*\.config/$rel_path" "$SYMLINKS_SCRIPT"; then
        local insert_line=$(grep -n "# Add more .config files as needed here" "$SYMLINKS_SCRIPT" | tail -1 | cut -d: -f1)
        local cmd="ln -sf \"\$HOME_DIR/.config/$rel_path\" ~/.config/$rel_path"
        
        sed -i.bak "${insert_line}i\\
$cmd" "$SYMLINKS_SCRIPT"
        
        rm -f "${SYMLINKS_SCRIPT}.bak"
        echo "Added symlink command for ~/.config/$rel_path directory"
      fi
    fi
  done
  
  echo "Scan complete. You may now run ./scripts/create_symlinks.sh to create the symlinks."
}

# Run the main function
scan_config