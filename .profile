# all shells load this file in interactive mode (usually the -i switch)
export DOT_PROFILE_LOADED=1

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Add RVM to PATH for scripting. Make sure this is the last PATH variable change.
export PATH="$PATH:$HOME/Library/Python/3.8/bin:/Applications/IntelliJ IDEA.app/Contents/MacOS"

### MANAGED BY RANCHER DESKTOP START (DO NOT EDIT)
export PATH="/Users/john.lee/.rd/bin:$PATH"
### MANAGED BY RANCHER DESKTOP END (DO NOT EDIT)

source ~/.gusto/init.sh
