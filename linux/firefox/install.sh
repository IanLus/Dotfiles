#!/usr/bin/env bash
# Overlay windows/firefox onto the Linux Firefox profile. Does not vendor upstream FlexFox CSS.
#   bash linux/firefox/install.sh
#   bash linux/firefox/install.sh --install-flexfox
#   bash linux/firefox/install.sh --install-flexfox --no-proxy
#
# The downloads command is remapped by AutoConfig next to the firefox binary
# (needs a full quit/start, and sudo for a system install). On many Linux
# builds that shortcut is Ctrl+Shift+Y; Ctrl+J still focuses the search bar.
# Keep FlexFox version/hash in sync with windows/firefox/install.ps1.

set -euo pipefail

flexfox_version='v7.0.1'
flexfox_zip_name='FlexFox-v7.0.1.zip'
flexfox_zip_url="https://github.com/yuuqilin/FlexFox/releases/download/${flexfox_version}/${flexfox_zip_name}"
flexfox_sha256='0BF871B6D8FB7D3D93ADAF2C20D05910FCE8263B99623357157FA74ECCE83BB3'
default_proxy='http://127.0.0.1:7890'
overlay_files=(
  'user.js'
  'chrome/components/uc-user-settings.css'
)

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/../.." && pwd)
src="$repo/windows/firefox"

profile_path=''
install_flexfox=0
proxy=''
proxy_set=0
no_proxy=0
skip_autoconfig=0
firefox_dirs=()
flexfox_tmp=''

usage() {
  cat <<'EOF'
Usage: bash linux/firefox/install.sh [options]

  --profile PATH         Firefox profile directory
  --install-flexfox      Download and install FlexFox chrome/
  --proxy URL            Proxy for the FlexFox download (empty disables it)
  --no-proxy             Ignore env proxies and the default local proxy
  --firefox-dir PATH     Firefox application directory (repeatable)
  --skip-autoconfig      Do not install the downloads-panel shortcut hook
  -h, --help             Show this help
EOF
}

warn() {
  if [[ -t 2 ]]; then
    printf '\033[33m%s\033[0m\n' "$*" >&2
  else
    printf '%s\n' "$*" >&2
  fi
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

trim() {
  local value=$1
  value=${value#"${value%%[![:space:]]*}"}
  value=${value%"${value##*[![:space:]]}"}
  printf '%s' "$value"
}

cleanup_flexfox() {
  if [[ -n ${flexfox_tmp} ]]; then
    rm -rf -- "$flexfox_tmp"
    flexfox_tmp=''
  fi
}
trap cleanup_flexfox EXIT

resolve_proxy() {
  local name value
  if ((no_proxy)); then
    return 0
  fi
  if ((proxy_set)); then
    printf '%s' "$proxy"
    return 0
  fi
  for name in HTTPS_PROXY HTTP_PROXY ALL_PROXY https_proxy http_proxy all_proxy; do
    value=${!name-}
    value=$(trim "$value")
    if [[ -n $value ]]; then
      printf '%s' "$value"
      return 0
    fi
  done
  printf '%s' "$default_proxy"
}

is_firefox_app_dir() {
  local dir=$1
  [[ -d $dir ]] || return 1
  [[ -x $dir/firefox || -x $dir/firefox-bin || -x $dir/firefox-esr ]] || return 1
  [[ -f $dir/omni.ja || -f $dir/browser/omni.ja ]]
}

app_dir_from_path() {
  local path=$1 dir libdir token magic
  [[ -n $path ]] || return 1
  if [[ -d $path ]] && is_firefox_app_dir "$path"; then
    realpath "$path"
    return 0
  fi
  [[ -e $path ]] || return 1
  dir=$(dirname "$(realpath "$path")")
  if is_firefox_app_dir "$dir"; then
    printf '%s\n' "$dir"
    return 0
  fi
  [[ -f $path ]] || return 1
  magic=$(head -c 4 "$path" || true)
  # Don't scrape paths out of the firefox binary.
  [[ $magic == $'\x7fELF' ]] && return 1
  libdir=$(sed -n -E 's/^[[:space:]]*MOZ_LIBDIR=//p' "$path" | head -n 1 || true)
  libdir=${libdir%\"}
  libdir=${libdir#\"}
  libdir=${libdir%\'}
  libdir=${libdir#\'}
  if [[ -n $libdir ]] && is_firefox_app_dir "$libdir"; then
    realpath "$libdir"
    return 0
  fi
  while IFS= read -r token; do
    token=${token//\"/}
    token=${token//\'/}
    if is_firefox_app_dir "$token"; then
      realpath "$token"
      return 0
    fi
    if [[ -e $token ]] && is_firefox_app_dir "$(dirname "$token")"; then
      realpath "$(dirname "$token")"
      return 0
    fi
  done < <(grep -oE '/[^[:space:]'\''"]+' "$path" || true)
  return 1
}

is_readonly_mount() {
  local dir=$1 opts fstype
  case $dir in
    /snap/*) return 0 ;;
  esac
  command -v findmnt >/dev/null 2>&1 || return 1
  opts=$(findmnt -T "$dir" -no OPTIONS 2>/dev/null || true)
  fstype=$(findmnt -T "$dir" -no FSTYPE 2>/dev/null || true)
  [[ $fstype == squashfs ]] && return 0
  [[ ,$opts, == *,ro,* ]]
}

can_write_app_dir() {
  local dir=$1
  [[ -w $dir ]] || return 1
  if [[ -d $dir/defaults/pref ]]; then
    [[ -w $dir/defaults/pref ]]
  elif [[ -e $dir/defaults ]]; then
    [[ -w $dir/defaults ]]
  fi
}

copy_autoconfig_pair() {
  local dir=$1 use_sudo=$2
  local prefs_dir="$dir/defaults/pref"
  if ((use_sudo)); then
    sudo install -D -m 644 "$src/autoconfig/config.js" "$dir/config.js"
    sudo install -D -m 644 "$src/autoconfig/defaults/pref/config-prefs.js" "$prefs_dir/config-prefs.js"
  else
    mkdir -p -- "$prefs_dir"
    cp -f -- "$src/autoconfig/config.js" "$dir/config.js"
    cp -f -- "$src/autoconfig/defaults/pref/config-prefs.js" "$prefs_dir/config-prefs.js"
  fi
}

declare -a ff_install_dirs=()
declare -A ff_install_seen=()

consider_ff_install() {
  local resolved=''
  resolved=$(app_dir_from_path "$1" || true)
  [[ -n $resolved ]] || return 0
  if [[ -z ${ff_install_seen[$resolved]+x} ]]; then
    ff_install_seen[$resolved]=1
    ff_install_dirs+=("$resolved")
  fi
}

collect_install_dirs() {
  local raw candidate cmd pid exe
  ff_install_dirs=()
  ff_install_seen=()

  if ((${#firefox_dirs[@]})); then
    for raw in "${firefox_dirs[@]}"; do
      consider_ff_install "$raw"
    done
    if ((${#ff_install_dirs[@]} == 0)); then
      die "Not a Firefox install directory: ${firefox_dirs[*]}"
    fi
    return 0
  fi

  while read -r pid; do
    [[ -n $pid ]] || continue
    exe=$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)
    [[ -n $exe && -e $exe ]] || continue
    consider_ff_install "$exe"
  done < <(ps -eo pid,comm 2>/dev/null | awk '$2=="firefox" || $2=="firefox-bin" || $2=="firefox-esr" {print $1}')

  local -a candidates=(
    /usr/lib/firefox
    /usr/lib64/firefox
    /usr/lib/firefox-esr
    /usr/lib64/firefox-esr
    /usr/lib/firefox-developer-edition
    /opt/firefox
    /opt/firefox-esr
    /usr/local/lib/firefox
    "$HOME/firefox"
    "$HOME/.local/lib/firefox"
    /snap/firefox/current/usr/lib/firefox
    /var/lib/flatpak/app/org.mozilla.firefox/current/active/files/lib/firefox
    "$HOME/.local/share/flatpak/app/org.mozilla.firefox/current/active/files/lib/firefox"
  )
  for candidate in "${candidates[@]}"; do
    consider_ff_install "$candidate"
  done
  for cmd in firefox firefox-esr firefox-bin; do
    if command -v "$cmd" >/dev/null 2>&1; then
      consider_ff_install "$(command -v "$cmd")"
    fi
  done

  if ((${#ff_install_dirs[@]} == 0)); then
    die 'Could not find the Firefox application directory. Pass --firefox-dir or --skip-autoconfig.'
  fi
}

install_autoconfig() {
  local dir written=0
  local -a need_sudo=()
  collect_install_dirs
  for dir in "${ff_install_dirs[@]}"; do
    if is_readonly_mount "$dir"; then
      warn "AutoConfig skipped (read-only install): $dir"
      continue
    fi
    if can_write_app_dir "$dir"; then
      copy_autoconfig_pair "$dir" 0
      printf 'AutoConfig downloads panel: %s\n' "$dir"
      written=1
    else
      need_sudo+=("$dir")
    fi
  done
  if ((${#need_sudo[@]})); then
    command -v sudo >/dev/null 2>&1 || die 'Need root to write Firefox AutoConfig, and sudo was not found.'
    printf 'Need sudo to write Firefox AutoConfig next to the firefox binary...\n'
    for dir in "${need_sudo[@]}"; do
      copy_autoconfig_pair "$dir" 1
      [[ -f $dir/config.js ]] || die "AutoConfig was not written to $dir"
      printf 'AutoConfig downloads panel: %s\n' "$dir"
      written=1
    done
  fi
  if ((written == 0)); then
    warn 'AutoConfig was not installed. Snap and Flatpak application directories are read-only.'
    return 1
  fi
  return 0
}

profile_is_running() {
  local profile=$1
  [[ -e $profile/.parentlock || -e $profile/parent.lock ]]
}

startup_cache_dir() {
  local profile=$1 leaf base
  leaf=$(basename "$profile")
  case $profile in
    */.var/app/org.mozilla.firefox/.mozilla/firefox/*)
      base=${profile%/.mozilla/firefox/*}
      printf '%s\n' "$base/cache/mozilla/firefox/$leaf/startupCache"
      ;;
    */.mozilla/firefox/*)
      base=${profile%/.mozilla/firefox/*}
      printf '%s\n' "$base/.cache/mozilla/firefox/$leaf/startupCache"
      ;;
    *)
      printf '%s\n' "$HOME/.cache/mozilla/firefox/$leaf/startupCache"
      ;;
  esac
}

clear_startup_cache() {
  local profile=$1 cache
  cache=$(startup_cache_dir "$profile")
  [[ -d $cache ]] || return 0
  if profile_is_running "$profile"; then
    return 0
  fi
  rm -rf -- "$cache"
  printf 'Cleared Firefox startup cache\n'
}

resolve_profile_path() {
  local root=$1 rel=$2 is_relative=$3
  rel=${rel//\\//}
  if ((is_relative == 0)) || [[ $rel == /* ]]; then
    printf '%s\n' "$rel"
  else
    printf '%s\n' "$root/$rel"
  fi
}

read_profile_from_ini() {
  local ini=$1
  local root current='' path='' relative=1 default_flag=0 install_default=''
  local -a prof_paths=() prof_rel=() prof_def=()
  local line key value i picked=-1 norm
  root=$(dirname "$ini")

  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    line=$(trim "$line")
    [[ -z $line || $line == \#* || $line == \;* ]] && continue
    if [[ $line =~ ^\[(.+)\]$ ]]; then
      if [[ $current == Profile* && -n $path ]]; then
        prof_paths+=("$path")
        prof_rel+=("$relative")
        prof_def+=("$default_flag")
      fi
      current=${BASH_REMATCH[1]}
      path=''
      relative=1
      default_flag=0
      continue
    fi
    [[ $line == *=* ]] || continue
    key=$(trim "${line%%=*}")
    value=$(trim "${line#*=}")
    if [[ $current == Install* && $key == Default ]]; then
      install_default=$value
    elif [[ $current == Profile* ]]; then
      case $key in
        Path) path=$value ;;
        IsRelative)
          if [[ $value == 0 ]]; then relative=0; else relative=1; fi
          ;;
        Default)
          if [[ $value == 1 ]]; then default_flag=1; else default_flag=0; fi
          ;;
      esac
    fi
  done < "$ini"
  if [[ $current == Profile* && -n $path ]]; then
    prof_paths+=("$path")
    prof_rel+=("$relative")
    prof_def+=("$default_flag")
  fi

  if [[ -n $install_default ]]; then
    norm=${install_default//\\//}
    for i in "${!prof_paths[@]}"; do
      if [[ ${prof_paths[$i]//\\//} == "$norm" ]]; then
        picked=$i
        break
      fi
    done
    if ((picked < 0)); then
      resolve_profile_path "$root" "$install_default" 1
      return 0
    fi
  fi
  if ((picked < 0)); then
    for i in "${!prof_paths[@]}"; do
      if [[ ${prof_def[$i]} == 1 ]]; then
        picked=$i
        break
      fi
    done
  fi
  if ((picked < 0 && ${#prof_paths[@]} > 0)); then
    picked=0
  fi
  if ((picked < 0)); then
    die "Could not determine the Firefox profile path from $ini."
  fi
  resolve_profile_path "$root" "${prof_paths[$picked]}" "${prof_rel[$picked]}"
}

choose_profiles_ini() {
  local -a found=()
  local candidate prefer='' kind='' pid exe chosen=''
  for candidate in \
    "$HOME/.mozilla/firefox/profiles.ini" \
    "$HOME/snap/firefox/common/.mozilla/firefox/profiles.ini" \
    "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox/profiles.ini"
  do
    [[ -f $candidate ]] && found+=("$candidate")
  done
  if ((${#found[@]} == 0)); then
    die "Firefox profiles.ini not found. Looked under ~/.mozilla, snap, and flatpak."
  fi
  if ((${#found[@]} == 1)); then
    printf '%s\n' "${found[0]}"
    return 0
  fi

  while read -r pid; do
    [[ -n $pid ]] || continue
    exe=$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)
    case $exe in
      /snap/*) kind=snap ;;
      *org.mozilla.firefox*|*flatpak*) kind=flatpak ;;
      /*) kind=native ;;
    esac
    [[ -n $kind ]] && break
  done < <(ps -eo pid,comm 2>/dev/null | awk '$2=="firefox" || $2=="firefox-bin" || $2=="firefox-esr" {print $1}')

  case $kind in
    snap) prefer="$HOME/snap/firefox/common/.mozilla/firefox/profiles.ini" ;;
    flatpak) prefer="$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox/profiles.ini" ;;
    *) prefer="$HOME/.mozilla/firefox/profiles.ini" ;;
  esac
  for candidate in "${found[@]}"; do
    if [[ $candidate == "$prefer" ]]; then
      chosen=$candidate
      break
    fi
  done
  [[ -n $chosen ]] || chosen=${found[0]}
  warn "Multiple Firefox profiles.ini found; using $chosen"
  printf '%s\n' "$chosen"
}

get_profile_path() {
  local requested=$1 ini
  if [[ -n $requested ]]; then
    [[ -d $requested ]] || die "Profile path not found: $requested"
    realpath "$requested"
    return 0
  fi
  ini=$(choose_profiles_ini)
  read_profile_from_ini "$ini"
}

copy_overlay_file() {
  local from=$1 to=$2 parent
  [[ -f $from ]] || die "Missing overlay file: $from"
  parent=$(dirname "$to")
  mkdir -p -- "$parent"
  cp -f -- "$from" "$to"
  printf 'Copied %s\n' "$(basename "$to")"
}

ensure_wallpaper_import() {
  local path="$1/chrome/userContent.css"
  local import_line='@import url(./content/uc-custom-content.css);'
  local last
  if [[ ! -f $path ]]; then
    printf '%s\n' "$import_line" > "$path"
    printf 'Created chrome/userContent.css wallpaper import\n'
    return 0
  fi
  if grep -q 'uc-custom-content\.css' "$path"; then
    printf 'userContent.css already imports wallpaper CSS\n'
    return 0
  fi
  if [[ -s $path ]]; then
    last=$(tail -c 1 "$path" || true)
    if [[ -n $last && $last != $'\n' ]]; then
      printf '\n' >> "$path"
    fi
  fi
  printf '%s\n' "$import_line" >> "$path"
  printf 'Added wallpaper import to userContent.css\n'
}

install_homepage_wallpaper() {
  local profile=$1
  local chrome="$profile/chrome"
  mkdir -p -- "$chrome"
  copy_overlay_file "$src/chrome/wallpaper.png" "$chrome/wallpaper.png"
  copy_overlay_file "$src/chrome/wallpaper-light.png" "$chrome/wallpaper-light.png"
  # FlexFox uc.flex.newtab-background reads these names from chrome/
  copy_overlay_file "$src/chrome/wallpaper-light.png" "$chrome/background-0.png"
  copy_overlay_file "$src/chrome/wallpaper.png" "$chrome/background-1.png"
  copy_overlay_file "$src/chrome/content/uc-custom-content.css" "$chrome/content/uc-custom-content.css"
  ensure_wallpaper_import "$profile"
  printf 'Homepage wallpaper enabled\n'
}

set_toggle_shortcuts() {
  local profile=$1
  command -v python3 >/dev/null 2>&1 || die 'python3 is required to update Toggle shortcuts.'
  DOTFILES_FF_PROFILE=$profile DOTFILES_FF_SPEC=$src/toggle-shortcuts.json python3 - <<'PY'
import json
import os
import re
import time
from pathlib import Path

profile = Path(os.environ["DOTFILES_FF_PROFILE"])
spec = json.loads(Path(os.environ["DOTFILES_FF_SPEC"]).read_text(encoding="utf-8"))
settings_path = profile / "extension-settings.json"
now = int(time.time() * 1000)
if not settings_path.exists():
    settings_path.write_bytes(
        b'{"version":3,"url_overrides":{},"prefs":{},"default_search":{},"commands":{},"homepageNotification":{},"tabHideNotification":{},"newTabNotification":{}}'
    )
raw = settings_path.read_text(encoding="utf-8")
addon = str(spec["addonId"])
for style in spec["styles"]:
    shortcut = str(style.get("shortcut") or "")
    if not shortcut.strip():
        continue
    sid = str(style["id"])
    needle = f'"{sid}":{{"precedenceList":[{{"id":"{addon}"'
    entry = (
        f'"{sid}":{{"precedenceList":[{{"id":"{addon}","installDate":{now},'
        f'"value":{{"shortcut":"{shortcut}"}},"enabled":true}}]}}'
    )
    idx = raw.find(needle)
    if idx >= 0:
        tail = raw[idx:]
        match = re.search(r'"shortcut"\s*:\s*"[^"]*"', tail)
        if not match:
            raise SystemExit(f"Found Toggle command {sid} but no shortcut field in {settings_path}")
        raw = raw[:idx] + tail[: match.start()] + f'"shortcut":"{shortcut}"' + tail[match.end() :]
        print(f"Shortcut {shortcut} -> Toggle {sid}")
        continue
    replaced, count = re.subn(r'"commands"\s*:\s*\{\s*\}', '"commands":{' + entry + "}", raw, count=1)
    if count:
        raw = replaced
    else:
        replaced, count = re.subn(r'"commands"\s*:\s*\{', '"commands":{' + entry + ",", raw, count=1)
        if count:
            raw = replaced
        else:
            trimmed = raw.rstrip()
            if not trimmed.endswith("}"):
                raise SystemExit(f"Cannot insert Toggle shortcuts into {settings_path}")
            raw = trimmed[:-1] + ',"commands":{' + entry + "}}"
    print(f"Shortcut {shortcut} -> Toggle {sid} (inserted)")
settings_path.write_bytes(raw.encode("utf-8"))
PY
}

save_url() {
  local url=$1 outfile=$2 download_proxy=$3
  command -v curl >/dev/null 2>&1 || die 'curl is required to download FlexFox.'
  local -a args=(-fsSL --retry 3 -o "$outfile" "$url")
  if [[ -n $download_proxy ]]; then
    args=(-fsSL --retry 3 -x "$download_proxy" -o "$outfile" "$url")
  fi
  curl "${args[@]}" || die "Download failed: $url"
}

install_flexfox_chrome() {
  local profile=$1 download_proxy=$2 zip actual expected extracted chrome_src chrome_dst
  command -v sha256sum >/dev/null 2>&1 || die 'sha256sum is required to verify FlexFox.'
  flexfox_tmp=$(mktemp -d)
  zip=$flexfox_tmp/$flexfox_zip_name
  printf 'Downloading FlexFox %s ...\n' "$flexfox_version"
  save_url "$flexfox_zip_url" "$zip" "$download_proxy"
  actual=$(sha256sum "$zip" | awk '{print tolower($1)}')
  expected=$(printf '%s' "$flexfox_sha256" | tr '[:upper:]' '[:lower:]')
  [[ $actual == "$expected" ]] || die "FlexFox SHA256 mismatch. expected=$flexfox_sha256 actual=$actual"
  extracted=$flexfox_tmp/extracted
  mkdir -p -- "$extracted"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$zip" -d "$extracted"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -m zipfile -e "$zip" "$extracted"
  else
    die 'unzip or python3 is required to extract FlexFox.'
  fi
  chrome_src=$(find "$extracted" -type d -name chrome -print0 | while IFS= read -r -d '' dir; do
    if [[ -f $dir/userChrome.css ]]; then
      printf '%s\n' "$dir"
      break
    fi
  done)
  [[ -n $chrome_src ]] || die 'chrome/userChrome.css not found in FlexFox zip.'
  chrome_dst=$profile/chrome
  mkdir -p -- "$chrome_dst"
  cp -a -- "$chrome_src"/. "$chrome_dst"/
  printf 'Installed FlexFox %s chrome/\n' "$flexfox_version"
  cleanup_flexfox
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --profile)
      [[ $# -ge 2 ]] || die '--profile needs a path'
      profile_path=$2
      shift 2
      ;;
    --profile=*)
      profile_path=${1#*=}
      shift
      ;;
    --install-flexfox)
      install_flexfox=1
      shift
      ;;
    --proxy)
      [[ $# -ge 2 ]] || die '--proxy needs a URL'
      proxy=$2
      proxy_set=1
      shift 2
      ;;
    --proxy=*)
      proxy=${1#*=}
      proxy_set=1
      shift
      ;;
    --no-proxy)
      no_proxy=1
      shift
      ;;
    --firefox-dir)
      [[ $# -ge 2 ]] || die '--firefox-dir needs a path'
      firefox_dirs+=("$2")
      shift 2
      ;;
    --firefox-dir=*)
      firefox_dirs+=("${1#*=}")
      shift
      ;;
    --skip-autoconfig)
      skip_autoconfig=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -f $src/user.js ]] || die "Firefox overlay not found: $src"

profile=$(get_profile_path "$profile_path")
[[ -d $profile ]] || die "Firefox profile not found: $profile"
printf 'Firefox profile: %s\n' "$profile"
if profile_is_running "$profile"; then
  warn 'Firefox looks running (.parentlock). CSS can still be copied; user.js applies on the next full quit/start.'
fi

download_proxy=$(resolve_proxy)
if ((install_flexfox)); then
  if [[ -n $download_proxy ]]; then
    printf 'Using proxy: %s\n' "$download_proxy"
  fi
  install_flexfox_chrome "$profile" "$download_proxy"
fi

if [[ ! -f $profile/chrome/userChrome.css ]]; then
  warn 'chrome/userChrome.css is missing. Re-run with --install-flexfox to fetch the theme.'
fi

for rel in "${overlay_files[@]}"; do
  copy_overlay_file "$src/$rel" "$profile/$rel"
done

install_homepage_wallpaper "$profile"
set_toggle_shortcuts "$profile"

autoconfig_ok=1
if ((skip_autoconfig)); then
  printf 'Skipped AutoConfig (the downloads shortcut still opens the Library window).\n'
else
  [[ -f $src/autoconfig/config.js && -f $src/autoconfig/defaults/pref/config-prefs.js ]] || die "Missing AutoConfig files under $src/autoconfig"
  if install_autoconfig; then
    clear_startup_cache "$profile"
  else
    autoconfig_ok=0
  fi
fi

printf '\n'
printf 'Overlay applied. Fully quit Firefox and reopen so user.js, wallpaper, shortcuts, and the downloads panel take effect.\n'
if profile_is_running "$profile"; then
  warn 'Firefox is running; quit fully before the downloads shortcut can open the panel. If it still opens a window, use about:support -> Clear startup cache.'
fi
printf 'Toggle style names still need Apply changes in the extension options; see windows/firefox/notes.txt\n'
printf 'On many Linux builds the downloads shortcut is Ctrl+Shift+Y, not Ctrl+J.\n'
if ((autoconfig_ok == 0)); then
  exit 1
fi
