eval "$(fzf --zsh)"
# vim ~/**<tab> runs fzf_compgen_path() with the prefix (~/) as the first argument
# cd foo**<tab> runs fzf_compgen_dir() with the prefix (foo) as the first argument
_fzf_compgen_path() {
  "$DOTDIR/fzf/fd-toggle.sh" list "${1:-.}"
}

# Use fd to generate the list for directory completion
_fzf_compgen_dir() {
  fd --type d --hidden --follow --exclude ".git" . "$1"
}

# Advanced customization of fzf options via _fzf_comprun function
# - The first argument to the function is the name of the command.
# - You should make sure to pass the rest of the arguments to fzf.
_fzf_comprun() {
  local command=$1
  shift

  case "$command" in
    cd)           fzf --preview 'tree -C {} | head -200'   "$@" ;;
    export|unset) fzf --preview "eval 'echo \$'{}"         "$@" ;;
    ssh)          fzf --preview 'dig {}'                   "$@" ;;
    v|vi|nvim|vim)  fzf --preview 'bat --color=always -n --line-range=:500 {}' "$@" ;;
    *)            fzf --preview 'bat -n --color=always {}' "$@" ;;
  esac
}

# 从 git status 选文件并用 $EDITOR 打开；预览为该文件的 git diff。
# 路径解析 / diff 预览见 fzf/vgs.lua（zsh 与 Clink 共用）。
vgs() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    print -u2 'vgs: not a git repository'
    return 1
  }

  local helper="$DOTDIR/fzf/vgs-file.sh"
  local list
  list=$("$helper" list) || return
  if [[ -z $list ]]; then
    print -u2 'vgs: working tree clean'
    return 0
  fi

  print -r -- "$list" |
    fzf --ansi --nth=2.. \
      --preview-window=50% \
      --preview "'$helper' preview {}" \
      --bind "ctrl-/:change-preview-window(down|hidden|)" \
      --bind "enter:become:'$helper' open {}"
}
