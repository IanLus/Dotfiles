#!/usr/bin/env bash
# Thin wrapper: shared logic lives in fzf/vgs.lua.
set -euo pipefail

lua=$(command -v lua || command -v lua5.4 || command -v lua5.3 || true)
if [[ -z $lua ]]; then
  echo "vgs: lua not found" >&2
  exit 1
fi

exec "$lua" "${DOTDIR}/fzf/vgs.lua" "$@"
