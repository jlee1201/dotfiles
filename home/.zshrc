# Dynamic theme switching for Cursor vs normal terminal usage
# Detect if we're in a Cursor execution context
CURSOR_CONTEXT=""
if [[ -n "$CURSOR_SESSION" ]] || [[ -n "$VSCODE_INJECTION" ]] || [[ "$TERM_PROGRAM" == "cursor" ]] || [[ "$TERM_PROGRAM" == "vscode" ]] || pgrep -f "cursor" >/dev/null 2>&1; then
    CURSOR_CONTEXT="true"
fi

# Path to your oh-my-zsh installation.
export ZSH="/Users/john.lee/.oh-my-zsh"

# Set theme based on context
if [[ -n "$CURSOR_CONTEXT" ]]; then
    # Use robbyrussell theme when in Cursor context
    ZSH_THEME="robbyrussell"
else
    # Use Powerlevel10k for normal terminal usage
    ZSH_THEME="powerlevel10k/powerlevel10k"
    
    # Enable Powerlevel10k instant prompt only when using p10k theme
    # Initialization code that may require console input (password prompts, [y/n]
    # confirmations, etc.) must go above this block; everything else may go below.
    if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
      source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
    fi
fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
# DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to automatically update without prompting.
DISABLE_UPDATE_PROMPT="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_ZSH_DAYS=13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=( git zsh-syntax-highlighting zsh-autosuggestions docker docker-compose )

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
alias y="yarn --silent"

# Theme switching functions
switch_to_robbyrussell() {
    export ZSH_THEME="robbyrussell"
    source $ZSH/oh-my-zsh.sh
    echo "Switched to robbyrussell theme"
}

switch_to_p10k() {
    export ZSH_THEME="powerlevel10k/powerlevel10k"
    source $ZSH/oh-my-zsh.sh
    [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
    echo "Switched to Powerlevel10k theme"
}

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
# Only load p10k config when using Powerlevel10k theme
if [[ "$ZSH_THEME" == "powerlevel10k/powerlevel10k" ]]; then
    [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
fi



# autoload zfunc
for file in ~/.zfunc/*;
    do autoload $file
done

# moved MISE COONFIG location so need this
export GUSTO_MISE_ALLOW_IDIOMATIC_FILE_OVERRIDE=true

# load .profile if it hasn't been loaded yet (make changes to this file)
if [ -z "$DOT_PROFILE_LOADED" ]; then source ~/.profile; fi


# AsyncAPI CLI Autocomplete

ASYNCAPI_AC_ZSH_SETUP_PATH=/Users/john.lee/Library/Caches/@asyncapi/cli/autocomplete/zsh_setup && test -f $ASYNCAPI_AC_ZSH_SETUP_PATH && source $ASYNCAPI_AC_ZSH_SETUP_PATH; # asyncapi autocomplete setup




