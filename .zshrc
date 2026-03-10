# ============================================================================
# .zshrc
# ============================================================================
# Copyright (c) 2025 Michael Gardner, A Bit of Help, Inc.
# SPDX-License-Identifier: BSD-3-Clause
# See LICENSE file in the project root.
# ============================================================================
#
# Container-aware Zsh configuration for development environments.
# This configuration helps prevent common mistakes:
# - editing files in the wrong terminal
# - confusing host and container environments
# - forgetting which toolchain path is active
# - debugging mount and user issues more slowly than necessary
#
# It is lightweight, readable, and editor-agnostic.
# ============================================================================

export CHARSET=UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export TMPDIR=/tmp

[[ -o interactive ]] || return
[[ "$TERM" = "dumb" ]] && export TERM=xterm-256color

unset PS1 RPS1 RPROMPT PROMPT_COMMAND 2>/dev/null

# Container detection — trust entrypoint-exported markers first, then fall
# back to sentinel files and cgroup inspection for portability.
if [[ -n "$IN_CONTAINER" ]] && (( IN_CONTAINER )); then
    # Already set by entrypoint.sh.  CONTAINER_RUNTIME is also exported.
    :
elif [[ -f /.dockerenv ]]; then
    export IN_CONTAINER=1
    export CONTAINER_RUNTIME="docker"
elif [[ -f /run/.containerenv ]]; then
    export IN_CONTAINER=1
    export CONTAINER_RUNTIME="container"
elif grep -qaE '(docker|containerd|kubepods|podman)' /proc/1/cgroup 2>/dev/null; then
    export IN_CONTAINER=1
    export CONTAINER_RUNTIME="container"
else
    export IN_CONTAINER=0
    export CONTAINER_RUNTIME=""
fi

# Shell options
setopt AUTO_CD
setopt AUTO_PUSHD
setopt EXTENDED_GLOB
setopt INTERACTIVE_COMMENTS
setopt NO_BEEP
setopt PUSHD_IGNORE_DUPS

# History
HISTFILE="$HOME/.zsh_history"
HISTFILESIZE=999999
HISTSIZE=200000
SAVEHIST=200000

setopt APPEND_HISTORY
setopt EXTENDED_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt HIST_SAVE_NO_DUPS
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY

# Completion
export FPATH="$HOME/.docker/completions:$FPATH"

autoload -Uz compinit
compinit -u -d "$HOME/.zcompdump"

zstyle ':completion:*' group-name ''
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'
zstyle ':completion:*' menu select
zstyle ':completion:*' verbose yes
zstyle ':completion:*:descriptions' format '%B%d%b'
zstyle ':completion:*:messages' format '%d'
zstyle ':completion:*:warnings' format 'No matches for: %d'

# Keybindings + history search
bindkey -e

HSS_LOADED=0
for f in \
  /usr/share/zsh-history-substring-search/zsh-history-substring-search.zsh \
  /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
do
  if [[ -f "$f" ]]; then
    source "$f"
    HSS_LOADED=1
    break
  fi
done

if (( HSS_LOADED )) && zle -l history-substring-search-up >/dev/null 2>&1; then
    bindkey '^P'   history-substring-search-up
    bindkey '^N'   history-substring-search-down
    bindkey '^[[A' history-substring-search-up
    bindkey '^[[B' history-substring-search-down
    bindkey '^[OA' history-substring-search-up
    bindkey '^[OB' history-substring-search-down
else
    autoload -Uz down-line-or-beginning-search up-line-or-beginning-search
    zle -N down-line-or-beginning-search
    zle -N up-line-or-beginning-search
    bindkey '^P'   up-line-or-beginning-search
    bindkey '^N'   down-line-or-beginning-search
    bindkey '^[[A' up-line-or-beginning-search
    bindkey '^[[B' down-line-or-beginning-search
    bindkey '^[OA' up-line-or-beginning-search
    bindkey '^[OB' down-line-or-beginning-search
fi

if command -v fzf >/dev/null 2>&1; then
    fzf-history-widget() {
        local selected
        selected=$(
            fc -rl 1 |
            sed 's/^[[:space:]]*[0-9]\+[[:space:]]*//' |
            fzf --tac --height 40%
        ) || return
        LBUFFER+="$selected"
        zle reset-prompt
    }
    zle -N fzf-history-widget
    bindkey '^R' fzf-history-widget
else
    bindkey '^R' history-incremental-search-backward
fi

# Prompt
autoload -Uz colors && colors
setopt PROMPT_SUBST

container_tag() {
    (( IN_CONTAINER )) || return 0
    print -n " %F{blue}[ctr:%B${CONTAINER_RUNTIME}%b]%f"
}

git_branch() {
    command git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
    local b
    b=$(command git symbolic-ref --short HEAD 2>/dev/null) || return 0
    print -n " %F{magenta}(${b})%f"
}

# Use DISPLAY_USER (set by entrypoint) to show the intended username in
# rootless mode where whoami returns "root".  Falls back to %n (effective user).
PROMPT=$'%(?..%F{red}✗%? %f)%F{green}${DISPLAY_USER:-%n}@%m%f %F{cyan}%~%f$(git_branch)$(container_tag)\n%F{yellow}❯%f '

# Tool environment
export EDITOR="${EDITOR:-nano}"
export GIT_TERMINAL_PROMPT=1
export LESS='-R -F -X'
export PAGER="${PAGER:-less}"

# Aliases — navigation
alias ..='cd ..'
alias ...='cd ../..'

# Aliases — Rust development
alias cb='cargo build'
alias cbr='cargo build --release'
alias cck='cargo check'
alias ccl='cargo clippy'
alias cf='cargo fmt'
alias cl='cargo clean'
alias cr='cargo run'
alias crr='cargo run --release'
alias ct='cargo test'
alias ctn='cargo test -- --nocapture'
alias cdoc='cargo doc --open'
alias cadd='cargo add'
alias cup='cargo update'

# Aliases — diagnostics
alias cenv='printenv | sort'
alias cid='cat /etc/hostname'
alias clr='clear'
alias cps='ps -ef'
alias cwho='echo "DISPLAY_USER=${DISPLAY_USER:-$(whoami)}"; id'
alias env='env | sort'

# Aliases — git
alias g='git'
alias gd='git diff'
alias gl='git log --oneline --decorate --graph --max-count=20'
alias gs='git status'

# Aliases — files and search
alias grep='grep --color=auto'
alias l='ls -CF'
alias la='ls -A'
alias ll='ls -alF'

# Python venv helpers
vinit() {
    local vpath="${1:-.venv}"
    local python_cmd="${2:-python3}"

    if ! command -v "$python_cmd" &>/dev/null; then
        echo "Error: '$python_cmd' not found"
        return 1
    fi

    if [[ -d "$vpath" ]]; then
        echo "Error: '$vpath' already exists"
        return 1
    fi

    "$python_cmd" -m venv "$vpath" && echo "Created: $vpath"
}

vact() {
    local dir="$PWD"
    local venv_names=(".venv" "env" "venv")

    while [[ "$dir" != "/" ]]; do
        for venv_name in "${venv_names[@]}"; do
            if [[ -f "$dir/$venv_name/bin/activate" ]]; then
                source "$dir/$venv_name/bin/activate"
                echo "Activated: $dir/$venv_name"
                return 0
            fi
        done
        dir="$(dirname "$dir")"
    done

    echo "No venv found in current or parent directories"
    return 1
}

vdact() {
    [[ -n "$VIRTUAL_ENV" ]] && deactivate || echo "No venv active"
}

container_info() {
    echo "IN_CONTAINER=${IN_CONTAINER}"
    echo "CONTAINER_RUNTIME=${CONTAINER_RUNTIME}"
    echo "DISPLAY_USER=${DISPLAY_USER:-$(whoami)}"
    echo "USER=$(whoami)"
    echo "UID=$(id -u)"
    echo "GID=$(id -g)"
    echo "HOME=$HOME"
    echo "PWD=$PWD"
    echo "HOSTNAME=$(hostname)"
    echo "---"
    rustc --version 2>/dev/null
    cargo --version 2>/dev/null
    rustup --version 2>/dev/null
    probe-rs --version 2>/dev/null
    mold --version 2>/dev/null
}

# Plugins
[[ -r /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] &&
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# MUST be last
[[ -r /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] &&
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
