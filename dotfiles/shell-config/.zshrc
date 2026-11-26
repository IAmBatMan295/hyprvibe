echo ""
POSH_THEME="${XDG_STATE_HOME:-$HOME/.local/state}/hyprvibe/current/zen.toml"
[[ ! -f "$POSH_THEME" ]] && POSH_THEME="$HOME/.config/ohmyposh/zen.toml"
eval "$(oh-my-posh init zsh --config "$POSH_THEME")"
eval "$(dircolors -b | sed 's/;4[0-9]//g')"

ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
[ ! -d "$ZINIT_HOME" ] && mkdir -p "$(dirname "$ZINIT_HOME")"
if [ ! -d "$ZINIT_HOME/.git" ]; then
  GIT_TERMINAL_PROMPT=0 timeout 8 git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME" 2>/dev/null || true
fi
[[ -r "${ZINIT_HOME}/zinit.zsh" ]] && source "${ZINIT_HOME}/zinit.zsh"

# Print newline at terminal start for proper oh-my-posh spacing

if (( $+functions[zinit] )); then
  zinit light zsh-users/zsh-syntax-highlighting
  zinit light zsh-users/zsh-completions
  zinit light zsh-users/zsh-autosuggestions
  zinit light Aloxaf/fzf-tab

  zinit snippet OMZP::git
  zinit snippet OMZP::archlinux
  zinit snippet OMZP::sudo
fi

autoload -Uz compinit
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) || ! -f ${ZDOTDIR:-$HOME}/.zcompdump ]]; then
  compinit
else
  compinit -C
fi

# Show hidden files in completions
setopt globdots

bindkey -e
bindkey '^j' history-search-backward
bindkey '^k' history-search-forward

HISTSIZE=10000
HISTFILE=~/.zshrc_history
SAVEHIST=10000
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_find_no_dups

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' menu no
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# fzf-tab configuration - show hidden files in preview
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls -A --color $realpath'
zstyle ':fzf-tab:complete:*:*' fzf-preview 'ls -A --color $realpath 2>/dev/null || echo "$realpath"'

# Include hidden files in fzf completion
if command -v fd >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='fd --hidden --exclude .git'
else
  export FZF_DEFAULT_COMMAND='find . -type f -o -type d'
fi
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

eval "$(fzf --zsh)"

# Dynamic FZF Theme Integration
FZF_THEME="${XDG_STATE_HOME:-$HOME/.local/state}/hyprvibe/current/fzf.zsh"
[[ -f "$FZF_THEME" ]] && source "$FZF_THEME"

alias ls='ls --color'
alias zshrc='nvim ~/.zshrc'

cpg() {
  cd "$HOME/Desktop/cpg" || return
}
rustpg() {
  cd "$HOME/Desktop/rustpg" || return
}
pypg() {
  cd "$HOME/Desktop/pythonpg" || return
}

# Cmake
#
cmrun() {
  if [ -z "$1" ]; then
    echo "Usage: cmrun <executable-name>"
    return 1
  fi

  local target="./build/$1"

  if [ ! -x "$target" ]; then
    echo "Executable '$target' not found or not executable."
    return 1
  fi

  "$target"
}
cmakebuild() {
  if [ "$1" = "-i" ]; then
    echo "[cmakebuild] Mode: INDIVIDUAL"
    rm -rf build compile_commands.json
    cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DBUILD_MODE=INDIVIDUAL || return 1
    ln -sf build/compile_commands.json .
    cmake --build build || return 1

  elif [ "$1" = "-m" ]; then
    echo "[cmakebuild] Mode: MERGED"
    rm -rf build compile_commands.json
    cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DBUILD_MODE=MERGED || return 1
    ln -sf build/compile_commands.json .
    cmake --build build || return 1

  else
    echo "Usage: cmakebuild -i | -m"
    return 1
  fi
}

cmbuild() {
  cmake --build build
}

cmclean() {
  echo "[cmclean] Removing build/ and compile_commands.json"
  rm -rf build compile_commands.json
}


# Added by Antigravity CLI installer
export PATH="$HOME/.local/bin:$PATH"
export QML_IMPORT_PATH="$HOME/.config/quickshell/Launcher${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"

