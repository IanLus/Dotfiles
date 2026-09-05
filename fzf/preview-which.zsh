#!/hint/zsh
# fzf-tab preview for which/whence/where/type.
# Preview runs in a new zsh, so aliases/functions are dumped from the parent first.

_dotfiles_which_defs=/tmp/fzf-tab-which-defs-$USER.zsh
_dotfiles_which_builtins=/tmp/fzf-tab-zshbuiltins-$USER.txt

_dotfiles_which_hl() {
  local lang=${1:-zsh}
  if (( $+commands[bat] )); then
    bat --color=always --style=plain --language=$lang --paging=never
  else
    cat
  fi
}

_dotfiles_which_builtin_help() {
  local cmd=$1 line show=0
  local prefix="     $cmd"
  if [[ ! -s $_dotfiles_which_builtins ]]; then
    MANWIDTH=${FZF_PREVIEW_COLUMNS:-88} man zshbuiltins 2>/dev/null | col -bx >| $_dotfiles_which_builtins || return 1
  fi
  while IFS= read -r line; do
    if [[ $line == $prefix || $line == $prefix' '* ]]; then
      show=1
      print -r -- "$line"
      continue
    fi
    if (( show )); then
      if [[ $line == '     '[^[:space:]]* && $line != $prefix && $line != $prefix' '* ]]; then
        break
      fi
      print -r -- "$line"
    fi
  done < $_dotfiles_which_builtins
}

# Cheap dump: aliases + already-loaded user functions only.
# Do not walk _ftb_compcap or autoload +X — which's candidate list is huge.
_dotfiles_dump_which_defs() {
  emulate -L zsh
  local k
  local -A _ftb_aliasdump _ftb_funcdump

  for k in ${(k)aliases}; do
    _ftb_aliasdump[$k]=$aliases[$k]
  done

  for k in ${(k)functions:#([_.]*|-*|prompt_*|instant_prompt_*)}; do
    [[ $functions[$k] == *$'\tautoload '* ]] && continue
    (( $#functions[$k] > 20000 )) && continue
    _ftb_funcdump[$k]=$functions[$k]
  done

  { typeset -p _ftb_aliasdump; typeset -p _ftb_funcdump } >| $_dotfiles_which_defs
}

_dotfiles_ftb_popup() {
  case ${words[1]:t} in
    which|whence|where|type) _dotfiles_dump_which_defs ;;
  esac
  ftb-tmux-popup "$@"
}

_dotfiles_preview_which() {
  emulate -L zsh
  local word=${(Q)word} kind=${${group#\[}%\]}
  [[ -r $_dotfiles_which_defs ]] && source $_dotfiles_which_defs

  if [[ -z $kind || $kind == __hide__* ]]; then
    if (( $+_ftb_aliasdump[$word] )); then
      kind=alias
    elif (( $+_ftb_funcdump[$word] )); then
      kind='shell function'
    elif (( $+builtins[$word] )); then
      kind='builtin command'
    elif (( ${reswords[(Ie)$word]} )); then
      kind='reserved word'
    else
      kind='external command'
    fi
  fi

  case $kind in
    alias|*alias*)
      if (( $+_ftb_aliasdump[$word] )); then
        print -r -- "$word is an alias for"
        print -r -- "$_ftb_aliasdump[$word]" | _dotfiles_which_hl zsh
      else
        print -r -- "$word is an alias (definition unavailable in preview)"
      fi
      ;;
    *function*)
      if [[ -n $_ftb_funcdump[$word] ]]; then
        print -r -- "$word () {
$_ftb_funcdump[$word]
}" | _dotfiles_which_hl zsh
      else
        print -r -- "$word is a shell function"
      fi
      ;;
    *builtin*)
      print -r -- "$word is a shell builtin"
      print
      _dotfiles_which_builtin_help $word | _dotfiles_which_hl man
      ;;
    *reserved*)
      print -r -- "$word is a reserved word"
      ;;
    *)
      local exe=${realpath:-$(whence -p -- $word 2>/dev/null)}
      if [[ -n $exe && -e $exe ]]; then
        print -r -- "$exe"
        file -b -- ${(Q)exe}
      else
        whence -va -- $word 2>/dev/null || print -r -- "$word ($kind)"
      fi
      ;;
  esac
}
