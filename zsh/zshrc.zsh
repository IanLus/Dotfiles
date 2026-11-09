# 此文件优先级最高（最后应用，将覆盖前面所应用的所有重复配置）
# 根据不同的 vi 模式更改光标形状
function zle-keymap-select {
  if [[ $KEYMAP == vicmd ]] || [[ $1 == 'block' ]]; then
    echo -ne '\e[1 q'  # 使用 Filled box 形状
  elif [[ $KEYMAP == main ]] || [[ $KEYMAP == viins ]] || [[ $KEYMAP == '' ]] || [[ $1 == 'beam' ]]; then
    echo -ne '\e[5 q'  # 使用 bar 形状
  fi
}
zle -N zle-keymap-select
# 在启动时使用 bar 形状的光标
echo -ne '\e[5 q'

bindkey -v # CLI可使用vim模式
export KEYTIMEOUT=1
# Emacs
bindkey '^f' forward-char
bindkey '^b' backward-char
bindkey '^p' up-line-or-search
bindkey '^n' down-line-or-search
bindkey '^w' backward-kill-word
bindkey '^u' backward-kill-line
bindkey '^y' yank
bindkey '^a' beginning-of-line
bindkey '^e' end-of-line
bindkey '^q' push-line-or-edit
bindkey '^k' kill-line
bindkey '^[f' forward-word
bindkey '^[b' backward-word
# forward-word / backward-word 的边界由 $WORDCHARS 决定，默认值里带 / - . _ 等，
# 于是 /hello/world、foo-bar、a.b、x_y 都会被当成一个词。把它们当分隔符用。
WORDCHARS=${WORDCHARS//[.\/_-]/}

# dsh-tui / dst 在 SSH、嵌套终端里会读不到扩展键。加一层包装，默认退回传统按键；
# 真要扩展键时用 `command dst` 绕过这层函数。
for _dsh_cmd in dst dsh-tui; do
  (( $+commands[$_dsh_cmd] )) || continue
  functions[$_dsh_cmd]="DSH_TUI_DISABLE_EXTENDED_KEYS=1 command $_dsh_cmd \"\$@\""
done
unset _dsh_cmd

# == fzf-tab
zstyle ':fzf-tab:complete:__zoxide_z_complete:*' query-string input
# preview of full commandline arguments
# give a preview of commandline arguments when completing `kill|ps`
zstyle ':completion:*:*:*:*:processes' command "ps -u $USER -o pid,user,comm,cmd -w -w"
zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-preview \
  '[[ $group == "[process ID]" ]] && ps --pid=$word -o cmd --no-headers -w -w'
zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-flags '--preview-window=down:3:wrap'
zstyle ':fzf-tab:complete:kill:*' popup-pad 0 3

# custom fzf flags
# NOTE: fzf-tab does not follow FZF_DEFAULT_OPTS by default
zstyle ':fzf-tab:*' fzf-flags --height='80%' --color=bg+:23,border:#cceeff \
  --border=rounded -e --ansi --preview-window='50%' \
  --tiebreak=begin,length \
  --bind 'ctrl-/:change-preview-window(down|hidden|),ctrl-f:preview-page-down,ctrl-b:preview-page-up'
# enable tmux popup for fzf to show results
[[ -f $DOTDIR/fzf/preview-which.zsh ]] && source $DOTDIR/fzf/preview-which.zsh
zstyle ':fzf-tab:*' fzf-command _dotfiles_ftb_popup
# set the lines number of fzf's prompt occupied
zstyle ':fzf-tab:*' fzf-pad 4
# bind <space> to accept the selected item
# zstyle ':fzf-tab:*' fzf-bindings 'space:accept'

zstyle ':completion:*' file-sort modification
zstyle ':completion:*:eza' sort false
zstyle ':completion:files' sort false

# disable sort when completing `git checkout`
zstyle ':completion:*:git-checkout:*' sort false
zstyle ':fzf-tab:complete:git-(add|diff|restore):*' fzf-preview \
	'git diff $word | delta'
zstyle ':fzf-tab:complete:git-log:*' fzf-preview \
	'git log --color=always $word'
zstyle ':fzf-tab:complete:git-help:*' fzf-preview \
	'git help $word | bat -plman --color=always'
zstyle ':fzf-tab:complete:git-show:*' fzf-preview \
	'case "$group" in
	"commit tag") git show --color=always $word ;;
	*) git show --color=always $word | delta ;;
	esac'
zstyle ':fzf-tab:complete:git-checkout:*' fzf-preview \
	'case "$group" in
	"modified file") git diff $word | delta ;;
	"recent commit object name") git show --color=always $word | delta ;;
	*) git log --color=always $word ;;
	esac'

# set descriptions format to enable group support
# NOTE: don't use escape sequences here, fzf-tab will ignore them
zstyle ':completion:*:descriptions' format '[%d]'
# set list-colors to enable filename colorizing
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
# force zsh not to show completion menu, which allows fzf-tab to capture the unambiguous prefix
zstyle ':completion:*' menu no
# preview directory's content with eza when completing cd
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 -a --color=always $realpath'
# set the right and bottom padding of the popup window
zstyle ':fzf-tab:complete:cd:*' popup-pad 30 0
# set the minimum size of the popup window in tmux
# apply to all command
zstyle ':fzf-tab:*' popup-min-size 120 50
# set minimal height of fzf's prompt
# zstyle ':fzf-tab:*' fzf-min-height 80
# only apply to 'diff'
zstyle ':fzf-tab:complete:diff:*' popup-min-size 80 16
# switch group using `<` and `>`
zstyle ':fzf-tab:*' switch-group '<' '>'
# default active-group-style is bold, too faint on already-colored headers
zstyle ':fzf-tab:*' active-group-style bold underline
# set case insensitive when change directory with cd
zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]} l:|=* r:|=*' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]} l:|=* r:|=*' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]} l:|=* r:|=*'
zstyle ':completion:*:*:docker:*' option-stacking yes
zstyle ':completion:*:*:docker-*:*' option-stacking yes
# show systemd unit status（--user 选管理器、空候选保护等细节见 fzf/README.md）
zstyle ':fzf-tab:complete:systemctl-*:*' fzf-preview \
  '[[ -n $word ]] && SYSTEMD_COLORS=1 SYSTEMD_URLIFY=0 systemctl ${${words[(Ie)--user]:#0}:+--user} status -- "$word"'

# pacman / paru：包名、仓库名、包组名都不是文件，realpath 为空，走 lessfilter 的 cat 会报错。
# 按操作（-S/-Q/-F/-U…）和修饰符（-i/-l/-g/-o…）选对应的 pacman 查询来预览。
if [[ -f $DOTDIR/fzf/preview-pacman.zsh ]]; then
  source $DOTDIR/fzf/preview-pacman.zsh
  zstyle ':fzf-tab:complete:(pacman|pacman-conf|paru|yay|pikaur):*' fzf-preview \
    'source ${(q)DOTDIR}/fzf/preview-pacman.zsh && _dotfiles_preview_pacman'
fi

# show file contents（图片走 lessfilter 的 sixel，与 Ctrl+T / ** 一致）
zstyle ':fzf-tab:complete:*:*' fzf-preview '$DOTDIR/less/lessfilter.sh ${(Q)realpath}'
# To disable or override preview for command options and subcommands, use
zstyle ':fzf-tab:complete:*:options' fzf-preview
zstyle ':fzf-tab:complete:*:argument-1' fzf-preview
zstyle ':fzf-tab:complete:systemctl:argument-rest' fzf-preview
zstyle ':fzf-tab:complete:(__zoxide_z_complete|tmux*|docker*|pkill*|git-stash):*' fzf-preview
# 命令位（gs<Tab>）以及 which/type：预览别名/函数/内置（定义由 _dotfiles_ftb_popup 导出）
zstyle ':fzf-tab:complete:(-command-|which|whence|where|type):*' fzf-preview \
  "source ${(q)DOTDIR}/fzf/preview-which.zsh && _dotfiles_preview_which"
# 命令位和 which 都去掉 _git / p10k / zinit 等内部函数
zstyle ':completion:*:*:(-command-|which|whence|where|type):functions' ignored-patterns \
  '[_.]*' '-*' 'prompt_*' 'instant_prompt_*'
zstyle ':completion:*:*:(-command-|which|whence|where|type):*' extra-verbose false
zstyle ':completion:*:*:(which|whence|where|type):*' tag-order \
  'aliases functions builtins reserved-words commands'

# environment variable
zstyle ':fzf-tab:complete:(-parameter-|-brace-parameter-|export|unset|expand):*' \
	fzf-preview 'echo ${(P)word}'

compdef _mv advmv
compdef _cp advcp

[[ -f $DOTDIR/aliases ]] && source $DOTDIR/aliases
(( $+functions[_dotfiles_dump_which_defs] )) && _dotfiles_dump_which_defs
if (( $+_dotfiles_which_builtins )) && [[ ! -s $_dotfiles_which_builtins ]]; then
  { man zshbuiltins 2>/dev/null | col -bx >| $_dotfiles_which_builtins } >/dev/null 2>&1 &!
fi
[[ -f $DOTDIR/fzf/fzf.zsh ]] && source $DOTDIR/fzf/fzf.zsh
[[ -f $XDG_CONFIG_HOME/cargo/env ]] && source $XDG_CONFIG_HOME/cargo/env
[[ -f $HOME/.openclaw/completions/openclaw.zsh ]] && source $HOME/.openclaw/completions/openclaw.zsh
[[ -f $DOTDIR/completions/hf/_hf ]] && source $DOTDIR/completions/hf/_hf
[[ -f $DOTDIR/completions/claude/_claude ]] && source $DOTDIR/completions/claude/_claude

# >>> conda initialize >>>
[ -f /opt/miniforge/etc/profile.d/conda.sh ] && source /opt/miniforge/etc/profile.d/conda.sh
# <<< conda initialize <<<

# mamba：启动不跑 hook。activate / 装包后 reactivate 才加载。
export MAMBA_EXE='/opt/miniforge/bin/mamba'
export MAMBA_ROOT_PREFIX='/opt/miniforge'
_dotfiles_mamba_hook() {
  unfunction _dotfiles_mamba_hook mamba
  local setup
  setup="$("$MAMBA_EXE" shell hook --shell zsh --root-prefix "$MAMBA_ROOT_PREFIX" 2>/dev/null)" || {
    mamba() { "$MAMBA_EXE" "$@" }
    mamba "$@"
    return
  }
  eval "$setup"
  mamba "$@"
}
mamba() {
  case ${1:-} in
    activate|reactivate|deactivate|install|update|upgrade|remove|uninstall)
      _dotfiles_mamba_hook "$@"
      ;;
    *)
      "$MAMBA_EXE" "$@"
      ;;
  esac
}

[[ -f $DOTDIR/zsh/proxy.zsh ]] && source $DOTDIR/zsh/proxy.zsh

command -v zoxide >/dev/null && eval "$(zoxide init zsh | sed 's/^function zi(/function zf(/')"
