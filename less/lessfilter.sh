#!/usr/bin/env bash
# this is a example of .lessfilter, you can change it
mime=$(file -bL --mime-type "$1")
category=${mime%%/*}
kind=${mime##*/}
file=${1/#\~\//$HOME/}
if [ -d "$file" ]; then
  eza --git -ahl --color=always --icons=always "$file"
elif [ "$category" = image ]; then
  dim=${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}
  if [[ $dim == x ]]; then
    dim=$(stty size </dev/tty 2>/dev/null | awk '{print $2 "x" $1}')
  elif [[ -n $FZF_PREVIEW_LINES ]]; then
    # 预留一行，避免 fzf 按 sixel 条带估高溢出后改画线框。
    # * https://github.com/junegunn/fzf/issues/2544
    dim=${FZF_PREVIEW_COLUMNS}x$((FZF_PREVIEW_LINES - 1))
  fi

  # 1. Use icat (from Kitty) if kitten is installed
  if [[ $KITTY_WINDOW_ID ]] || [[ $GHOSTTY_RESOURCES_DIR ]] && command -v kitten >/dev/null; then
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
  in2csv "$file" | xsv table | bat -n -ltsv --color=always
elif [[ "$category" = "text" || "$kind" == "javascript" ]]; then
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
  # Sometimes bat is installed as batcat.
  if command -v batcat >/dev/null; then
    batname="batcat"
  elif command -v bat >/dev/null; then
    batname="bat"
  fi
  ${batname} --style="${BAT_STYLE:-numbers}" --color=always --pager=never --highlight-line="${center:-0}" -- "$file"

elif [[ "$kind" == "json" ]]; then
  jq --color-output . "$file"
  # bat -n --color=always "$file"
else
  lesspipe.sh "$file"
fi
# lesspipe.sh don't use eza, bat and chafa, it use ls and exiftool. so we create a lessfilter.
