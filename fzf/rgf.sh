#!/usr/bin/env bash
# rgf 的辅助脚本：给 fzf 喂「包含关键词的文件列表」。
#   rgf.sh list <query>           当前目录下内容匹配 query 的文件（一行一个）
#   rgf.sh preview <file> <query> 预览：定位到命中行并高亮匹配词
#
# 列表就是纯文件名，所以条目里既不需要字段分隔符，也不能带颜色：
# fzf 接受选中项时会把原始行原样吐出来，带 ANSI 的话路径会被污染。
set -euo pipefail

cmd=${1:-}
shift || true

case $cmd in
list)
  q=${1-}
  # 空查询不跑 rg：否则整个目录所有文件都会倒进 fzf
  [[ -n ${q//[[:space:]]/} ]] || exit 0
  # --fixed-strings：按字面量搜，避免用户敲的 . * ( 被当成正则炸掉 rg
  exec rg \
    --files-with-matches \
    --fixed-strings --smart-case \
    --color=never \
    --glob '!.git/' \
    --glob '!node_modules/' --glob '!target/' --glob '!dist/' \
    -- "$q" .
  ;;
preview)
  file=${1-} q=${2-}
  [[ -r $file ]] || { printf '无法读取：%s\n' "$file"; exit 0; }

  # 有查询词就用 rg 只显示命中处上下文：天然「跳到命中行」，且匹配词自带高亮。
  # -m 限制单文件命中数，避免大文件把预览塞满；只预览一个文件所以去掉文件名前缀。
  # 注意要直接 exec rg，别把输出先抓到变量再 printf：那样 fzf 预览里颜色会丢。
  if [[ -n ${q//[[:space:]]/} ]]; then
    rg --line-number --context=3 --max-count=20 --no-filename \
      --fixed-strings --smart-case --color=always \
      -e "$q" -- "$file" && exit 0
  fi

  # 没有命中（或查询为空）时退回整文件首屏，至少能看个大概
  if command -v bat >/dev/null 2>&1; then
    exec bat --style=numbers --color=always --pager=never --line-range=:300 -- "$file"
  fi
  exec sed -n '1,300p' -- "$file"
  ;;
*)
  printf 'usage: %s list <query> | preview <file> <query>\n' "$0" >&2
  exit 2
  ;;
esac
