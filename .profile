# all shells load this file in interactive mode (usually the -i switch)
export DOT_PROFILE_LOADED=1

eval "$(mise activate zsh --shims)"

export PATH="$PATH:$HOME/Library/Python/3.8/bin:/Applications/IntelliJ IDEA.app/Contents/MacOS"

source ~/.gusto/init.sh
