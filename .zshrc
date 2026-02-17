# -----------------------------------------------------
#  ZSH OPTIONS
# -----------------------------------------------------
setopt autocd
setopt correct
setopt interactivecomments

# History (better defaults)
setopt appendhistory
setopt incappendhistory
setopt sharehistory
setopt histignorealldups
setopt histignorespace
setopt histreduceblanks
setopt extendedhistory

HISTSIZE=10000
SAVEHIST=10000
HISTFILE="$HOME/.zsh_history"

# -----------------------------------------------------
#  SOURCE EXTERNAL CONFIG FILES (KEEP)
# -----------------------------------------------------
# Source zsh-configuration
if [[ -e ~/.config/zsh/zsh-config ]]; then
  source ~/.config/zsh/zsh-config
fi

# Use zsh prompt
if [[ -e ~/.config/zsh/zsh-prompt ]]; then
  source ~/.config/zsh/zsh-prompt
fi

# -----------------------------------------------------
#  ENV / DEFAULTS
# -----------------------------------------------------
export EDITOR="${EDITOR:-nvim}"
export VISUAL="${VISUAL:-nvim}"
export PAGER="${PAGER:-less}"
export LESS='-R -F -X -K'   # colors, quit if 1 screen, no clear on exit

# Ensure local bin first
export PATH="$HOME/.local/bin:$PATH"

# -----------------------------------------------------
#  ARCH PACMAN ALIASES
# -----------------------------------------------------
if [[ -f /etc/arch-release ]]; then
  alias pac-update='sudo pacman -Sy'
  alias pac-upgrade='sudo pacman -Syu'
  alias pac-upgrade-force='sudo pacman -Syyu'
  alias pac-install='sudo pacman -S'
  alias pac-remove='sudo pacman -Rs'
  alias pac-search='pacman -Ss'
  alias pac-package-info='pacman -Si'
  alias pac-installed-list='pacman -Qs'
  alias pac-installed-package-info='pacman -Qi'
  alias pac-clean='sudo pacman -Scc'
  alias po= 'sudo pacman -Rns $(pacman -Qdtq)'
fi

# -----------------------------------------------------
#  AUR HELPER DETECTION (SAFE)
# -----------------------------------------------------
aurhelper=""
if command -v yay >/dev/null 2>&1; then
  aurhelper="yay"
elif command -v paru >/dev/null 2>&1; then
  aurhelper="paru"
fi

# Only define AUR aliases if helper exists
if [[ -n "$aurhelper" ]]; then
  alias up="$aurhelper -Syu"
  alias un="$aurhelper -Rns"
  alias pl="$aurhelper -Qs"
  alias pa="$aurhelper -Ss"
fi

# -----------------------------------------------------
#  USEFUL ALIASES
# -----------------------------------------------------
alias c='clear'
alias ls='eza -1 --icons=auto'
alias l='eza -lh --icons=auto'
alias ll='eza -lha --icons=auto --group-directories-first'
alias lt='eza --tree --icons=auto'

alias ..='cd ..'
alias ...='cd ../..'
alias .3='cd ../../..'
alias .4='cd ../../../..'
alias .5='cd ../../../../..'

alias mkdir='mkdir -p'
alias vc='code'

# -----------------------------------------------------
#  GIT SHORTCUTS
# -----------------------------------------------------
alias gs='git status'
alias ga='git add .'
alias gc='git commit -m'
alias gp='git push'
alias gpl='git pull'
alias gcheck='git checkout'

# -----------------------------------------------------
#  YAZI (CD ON EXIT) - WORKS IN EXISTING TERMINAL
# -----------------------------------------------------
y() {
  local tmp cwd
  tmp="$(mktemp -t yazi-cwd.XXXXXX)" || return

  command yazi "$@" --cwd-file="$tmp"

  cwd="$(cat "$tmp" 2>/dev/null)"
  rm -f "$tmp"

  [[ -n "$cwd" && "$cwd" != "$PWD" ]] && cd "$cwd"
}

# -----------------------------------------------------
#  COMPLETION (FASTER)
# -----------------------------------------------------
autoload -Uz compinit
# Cache completion dump to speed up startup
ZSH_COMPDUMP="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
mkdir -p "${ZSH_COMPDUMP:h}"
compinit -d "$ZSH_COMPDUMP" -C

# -----------------------------------------------------
#  OPTIONAL: BETTER KEYBINDING FOR HISTORY SEARCH
#  (Up/Down search based on typed text)
# -----------------------------------------------------
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
eval "$(zoxide init zsh)"
