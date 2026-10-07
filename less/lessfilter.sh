#!/usr/bin/env bash
# this is a example of .lessfilter, you can change it
mime=$(file -bL --mime-type "$1")
category=${mime%%/*}
kind=${mime##*/}
file=${1/#\~\//$HOME/}

preview_text() {
  local target=$1
  local center=${2:-0}
  if command -v batcat >/dev/null 2>&1; then
    batcat --style="${BAT_STYLE:-numbers}" --color=always --pager=never --highlight-line="${center:-0}" -- "$target" && return 0
  elif command -v bat >/dev/null 2>&1; then
    bat --style="${BAT_STYLE:-numbers}" --color=always --pager=never --highlight-line="${center:-0}" -- "$target" && return 0
  fi
  cat -- "$target"
}

preview_yq() {
  command -v yq >/dev/null 2>&1 || return 1
  # mikefarah yq 用 -C；旧版 python-yq 用 eval --color-output。
  yq -C '.' "$1" 2>/dev/null || yq eval --color-output '.' "$1"
}

if [ -d "$file" ]; then
  if command -v eza >/dev/null 2>&1; then
    eza --git -ahl --color=always --icons=always "$file"
  else
    ls -la --color=always "$file" 2>/dev/null || ls -la "$file"
  fi
elif [ "$category" = image ]; then
  dim=${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}
  if [[ $dim == x ]]; then
    dim=$(stty size </dev/tty 2>/dev/null | awk '{print $2 "x" $1}')
  elif [[ -n $FZF_PREVIEW_LINES ]]; then
    # 预留一行，避免 fzf 按 sixel 条带估高溢出后改画线框。
    # * https://github.com/junegunn/fzf/issues/2544
    dim=${FZF_PREVIEW_COLUMNS}x$((FZF_PREVIEW_LINES - 1))
  fi

  # fzf 预览把输出接走，tmux 又不回答像素查询。用格子像素和 passthrough，
  # 让 icat 发出 unicode placeholder，由 kitty 在预览区把图画出来。
  if [[ -n ${TMUX-} ]] && command -v kitten >/dev/null; then
    cols=${FZF_PREVIEW_COLUMNS:-80}
    rows=${FZF_PREVIEW_LINES:-24}
    if ((rows > 1)); then
      rows=$((rows - 1))
    fi
    cell=$(tmux display-message -p '#{client_cell_width}x#{client_cell_height}' 2>/dev/null || true)
    cw=${cell%%x*}
    ch=${cell##*x}
    if [[ ! ${cw:-} =~ ^[1-9][0-9]*$ || ! ${ch:-} =~ ^[1-9][0-9]*$ ]]; then
      cw=10
      ch=20
    fi
    kitten icat --passthrough=tmux --stdin=no --transfer-mode=stream \
      --use-window-size "${cols},${rows},$((cols * cw)),$((rows * ch))" \
      --place="${cols}x${rows}@0x0" "$file" || true
  # 1. Use icat (from Kitty) if kitten is installed
  elif { [[ $KITTY_WINDOW_ID ]] || [[ $GHOSTTY_RESOURCES_DIR ]]; } && command -v kitten >/dev/null; then
    # 1. 'memory' is the fastest option but if you want the image to be scrollable,
    #    you have to use 'stream'.
    #
    # 2. The last line of the output is the ANSI reset code without newline.
    #    This confuses fzf and makes it render scroll offset indicator.
    #    So we remove the last line and append the reset code to its previous line.
    kitten icat --clear --transfer-mode=memory --unicode-placeholder --stdin=no --place="$dim@0x0" "$file" | sed '$d' | sed $'$s/$/\e[m/'

  # 2. chafa sixel。不要 --passthrough=tmux（fzf 会拆 DCS，漏出 tmux;），
  #    也不要 --clear（CSI 2J 清整屏）。自定义 tmux 已能解析裸 sixel。
  elif command -v chafa >/dev/null; then
    chafa -f sixels --probe=off --animate=off --polite=on \
      --passthrough=none -s "$dim" --stretch "$file"
    # Add a new line character so that fzf can display multiple images in the preview window
    echo

  # 3. If chafa is not found but imgcat is available, use it on iTerm2
  elif command -v imgcat >/dev/null; then
    # NOTE: We should use https://iterm2.com/utilities/it2check to check if the
    # user is running iTerm2. But for the sake of simplicity, we just assume
    # that's the case here.
    imgcat -W "${dim%%x*}" -H "${dim##*x}" "$file"
  fi
  if command -v exiftool >/dev/null; then
    exiftool "$file"
  fi

elif [ "$kind" = vnd.openxmlformats-officedocument.spreadsheetml.sheet ] ||
  [ "$kind" = vnd.ms-excel ]; then
  if command -v in2csv >/dev/null 2>&1 && command -v xsv >/dev/null 2>&1; then
    if command -v batcat >/dev/null 2>&1; then
      in2csv "$file" | xsv table | batcat -n -l tsv --color=always --pager=never
    elif command -v bat >/dev/null 2>&1; then
      in2csv "$file" | xsv table | bat -n -l tsv --color=always --pager=never
    else
      in2csv "$file" | xsv table
    fi
  else
    preview_text "$file"
  fi
else
  center=0
  if [[ ! -r $file ]]; then
    if [[ $file =~ ^(.+):([0-9]+)\ *$ ]] && [[ -r ${BASH_REMATCH[1]} ]]; then
      file=${BASH_REMATCH[1]}
      center=${BASH_REMATCH[2]}
    elif [[ $file =~ ^(.+):([0-9]+):[0-9]+\ *$ ]] && [[ -r ${BASH_REMATCH[1]} ]]; then
      file=${BASH_REMATCH[1]}
      center=${BASH_REMATCH[2]}
    fi
  fi

  ext=${file##*.}
  ext=${ext,,}
  doc=$kind
  case "$ext" in
  json) doc=json ;;
  yml | yaml) doc=yaml ;;
  esac

  # JSON / YAML 也是文本。能格式化就格式化，否则和普通文本一样走 bat，没有 bat 就 cat。
  if [[ "$doc" == json || "$kind" == json ]]; then
    if command -v jq >/dev/null 2>&1 && jq --color-output . "$file"; then
      :
    elif preview_yq "$file"; then
      :
    else
      preview_text "$file" "$center"
    fi
  elif [[ "$doc" == yaml || "$kind" == yaml || "$kind" == x-yaml || "$kind" == x-yml ]]; then
    if preview_yq "$file"; then
      :
    else
      preview_text "$file" "$center"
    fi
  elif [[ "$category" == text || "$kind" == javascript ]]; then
    preview_text "$file" "$center"
  elif command -v lesspipe.sh >/dev/null 2>&1; then
    lesspipe.sh "$file"
  else
    preview_text "$file" "$center"
  fi
fi
