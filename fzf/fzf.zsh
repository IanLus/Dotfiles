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
    *)            fzf --preview "${DOTDIR}/less/lessfilter.sh {}" "$@" ;;
  esac
}

# rgf：按「文件内容」找文件。敲 rgf 回车进 fzf，输入关键词实时列出当前目录下
# 内容命中的文件；回车把路径填入命令行，Ctrl-O 用 $EDITOR 打开。
# 列表生成与预览在 fzf/rgf.sh。
rgf() {
  local helper="$DOTDIR/fzf/rgf.sh"
  local result
  # --disabled：不让 fzf 自己过滤，列表完全由 rg 决定
  # --no-tmux：FZF_DEFAULT_OPTS 在 tmux 里会加 --tmux（浮动窗格），
  #   但走 tmux popup 时预览窗口的 ANSI 颜色会被过滤掉，命中词只剩加粗。
  #   rgf 的预览要靠颜色标出匹配位置，所以在命令行上覆盖回普通全屏。
  # --expect 输出两行：第一行是按下的键（回车为空行），之后是选中项。
  # 不能用 "arr=(${(f)"$(...)"})"——数组赋值会把开头的空行吞掉，键就对不齐了。
  result=$(printf '' | fzf --disabled --ansi --expect=ctrl-o \
    --no-tmux \
    --bind "change:reload-sync($helper list {q} || true)" \
    --preview "$helper preview {} {q}" \
    --preview-window=right:60% \
    --bind 'ctrl-/:change-preview-window(right:60%|down:60%|hidden|)' \
    --header 'enter: 填入路径    ctrl-o: 用 $EDITOR 打开' 2>/dev/null)

  local key=${result%%$'\n'*}
  local file=${result#*$'\n'}
  [[ -n $file ]] || return 1

  if [[ $key == ctrl-o ]]; then
    "${EDITOR:-nvim}" -- "$file"
  else
    # print -z 把内容塞进下一个提示符的编辑缓冲（等同 Ctrl+T 的效果）。
    # 必须用 -r：默认 print 会解释转义，${(q)} 生成的 '\ ' 反斜杠会被吃掉，
    # 带空格的文件名就又被拆回两个词了。
    print -rz -- ${(q)file}
  fi
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
