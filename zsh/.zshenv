#!/hint/zsh
export _ZL_DATA="$XDG_CONFIG_HOME/.zlua"
export _ZL_ECHO=1
export _ZL_MATCH_MODE=1
export _ZL_ADD_ONCE=1
export _ZL_ZSH_NO_FZF=1
export _ZL_ROOT_MARKERS=".git,.svn,.hg,.root,package.json,.vscode"
export _ZL_INT_SORT=1
export _ZL_HYPHEN=1
export FZ_HISTORY_CD_CMD="_zlua"
export RANGER_LOAD_DEFAULT_RC=false
export W3M_DIR=$XDG_CONFIG_HOME/.w3m
export HISTFILE="$XDG_CONFIG_HOME/zsh_history"
export HISTSIZE=10000
export SAVEHIST=10000
declare -A ZINIT          # initial Zinit's hash definition, if configuring before loading Zinit
# ZINIT[OPTIMIZE_OUT_DISK_ACCESSES]='1' # If set to 1, then Zinit will skip checking if a Turbo-loaded object exists on the disk.

# 已在 PATH 中则跳过，避免嵌套 zsh / exec zsh 重复拼接
_dotfiles_path_add() {
  local mode=prepend dir chunk
  [[ $1 == --append ]] && { mode=append; shift; }
  for dir in "$@"; do
    [[ -n $dir ]] || continue
    case ":$PATH:" in
      *:"$dir":*) continue ;;
    esac
    chunk="${chunk:+$chunk:}$dir"
  done
  [[ -n $chunk ]] || return
  if [[ $mode == append ]]; then
    PATH="$PATH:$chunk"
  else
    PATH="$chunk:$PATH"
  fi
}
_dotfiles_path_add \
  "$DOTDIR/bin" \
  "$XDG_DATA_HOME/bin" \
  "$XDG_DATA_HOME/bob/nvim-bin" \
  ${PNPM_HOME:+"$PNPM_HOME/bin"} \
  ${CARGO_HOME:+"$CARGO_HOME/bin"} \
  ${CUDA_HOME:+"$CUDA_HOME/bin"}
_dotfiles_path_add --append /usr/bin/vendor_perl
unset -f _dotfiles_path_add
export PATH
# 只给交互式 shell 初始化 fnm。nvim :terminal 是交互式，需要 --use-on-cd；
# :! / system() / 插件 job 是非交互，继承 nvim 的 PATH 即可，避免反复建 symlink。
if [[ -o interactive ]]; then
  eval "$(fnm env --use-on-cd --version-file-strategy=recursive --resolve-engines --shell zsh)"
  # fnm 不会在退出时删除本会话的 FNM_MULTISHELL_PATH 符号链接
  _dotfiles_fnm_cleanup() {
    if [[ -n $FNM_MULTISHELL_PATH && $FNM_MULTISHELL_PATH == *fnm_multishells* ]]; then
      rm -f -- "$FNM_MULTISHELL_PATH" 2>/dev/null
    fi
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook zshexit _dotfiles_fnm_cleanup
fi
