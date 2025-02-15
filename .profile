# all shells load this file in interactive mode (usually the -i switch)
export DOT_PROFILE_LOADED=1

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

export PATH="$PATH:$HOME/Library/Python/3.8/bin:/Applications/IntelliJ IDEA.app/Contents/MacOS"


source ~/.gusto/init.sh
