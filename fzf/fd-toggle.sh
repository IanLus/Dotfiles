#!/usr/bin/env bash
# fzf Ctrl-T / ** 补全：按状态文件列出文件，并输出 alt-h / alt-i 的 transform 动作。
#   list [root]              初始列表（不显示隐藏 / 遵守忽略规则）
#   hidden|ignore [root]     切换对应开关，向 stdout 打印 fzf actions
set -euo pipefail

ROOT_FILE="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/fzf-fd-root-${UID:-$USER}"
STATE_FILE="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/fzf-fd-state-${UID:-$USER}"

shquote() {
  printf "'%s'" "${1//\'/\'\\\'\'}"
}

run_fd() {
  local hidden=$1 ignore=$2 root=$3
  local -a flags=(--follow --color=always --exclude .git)
  if ((hidden)); then
    flags+=(--hidden)
  fi
  if ((ignore)); then
    flags+=(--no-ignore)
  fi
  fd "${flags[@]}" . "$root" || true
}

build_fd_cmd() {
  local hidden=$1 ignore=$2 root=$3
  local -a args=(fd --follow --color=always --exclude .git)
  if ((hidden)); then
    args+=(--hidden)
  fi
  if ((ignore)); then
    args+=(--no-ignore)
  fi
  args+=(. "$root")
  local cmd="" part
  for part in "${args[@]}"; do
    cmd+=" $(shquote "$part")"
  done
  printf '%s || true' "${cmd# }"
}

header_for() {
  local hidden=$1 ignore=$2
  local h=off i=off
  if ((hidden)); then
    h=on
  fi
  if ((ignore)); then
    i=on
  fi
  printf 'alt-h: hidden %s | alt-i: ignore %s' "$h" "$i"
}

load_state() {
  hidden=0
  ignore=0
  if [[ -r $STATE_FILE ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
}

save_state() {
  printf 'hidden=%s\nignore=%s\n' "$hidden" "$ignore" >"$STATE_FILE"
}

resolve_root() {
  local root=${1:-}
  if [[ -z $root && -f $ROOT_FILE ]]; then
    root=$(<"$ROOT_FILE")
  fi
  printf '%s' "${root:-.}"
}

save_root() {
  printf '%s\n' "$1" >"$ROOT_FILE"
}

cmd=${1:-list}
explicit_root=${2:-}

case $cmd in
  list)
    root=${explicit_root:-.}
    hidden=0
    ignore=0
    save_root "$root"
    save_state
    run_fd 0 0 "$root"
    ;;
  hidden | ignore)
    root=$(resolve_root "$explicit_root")
    load_state
    if [[ $cmd == hidden ]]; then
      hidden=$((1 - hidden))
    else
      ignore=$((1 - ignore))
    fi
    save_state
    printf 'change-header(%s)+reload(%s)\n' \
      "$(header_for "$hidden" "$ignore")" \
      "$(build_fd_cmd "$hidden" "$ignore" "$root")"
    ;;
  *)
    echo "usage: $0 list|hidden|ignore [root]" >&2
    exit 2
    ;;
esac
