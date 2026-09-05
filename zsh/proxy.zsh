#!/hint/zsh
# Clash / 本机代理开关。
# 非 WSL：默认 127.0.0.1:7890，只提供 proxy_on / off，不自动设。
# WSL：按网络模式选 host，启动时探测成功才自动设。
#
# WSL 模式（先确认是 WSL，再判断）：
#   - Mirrored：loopback0 存在 -> 127.0.0.1
#   - NAT：默认网关在 172.16.0.0/12 -> 网关 IP（需 Clash allow-lan）
#   - 仍不明再读 .wslconfig 的 networkingMode（9p，慢）
# lo 上 10.255.255.254 是 NAT 的 hostAddressLoopback，不能当镜像依据。
#
# 探测：Clash 没开一般是 RST，立刻失败；2s 只会出现在端口被黑洞时。
# 启动用 0.2s；proxy_on 仍用 2s。不可达就不设变量，避免请求卡在死代理上。

typeset -g _DOTFILES_PROXY_PORT=7890
typeset -gi _DOTFILES_IN_WSL=0
[[ -n $WSL_DISTRO_NAME || -f /proc/sys/fs/binfmt_misc/WSLInterop ]] && _DOTFILES_IN_WSL=1
_wsl_in_wsl() { (( _DOTFILES_IN_WSL )) }

# 用法：_dotfiles_port_open host port [timeout_secs]
# /dev/tcp 是 bash 特性，zsh 没有。
_dotfiles_port_open() {
  local host=$1 port=${2:-$_DOTFILES_PROXY_PORT} secs=${3:-0.2}
  [[ -n $host ]] || return 1
  if (( $+commands[timeout] )); then
    timeout "$secs" bash -c 'true < /dev/tcp/'"$host"'/'"$port" 2>/dev/null
  else
    bash -c 'true < /dev/tcp/'"$host"'/'"$port" 2>/dev/null
  fi
}

_dotfiles_set_proxy() {
  local host=$1
  if [[ -z $host ]]; then
    print -u2 'proxy: empty host'
    return 1
  fi
  export http_proxy="http://$host:$_DOTFILES_PROXY_PORT"
  export https_proxy=$http_proxy
  export HTTP_PROXY=$http_proxy
  export HTTPS_PROXY=$http_proxy
  export no_proxy="localhost,127.0.0.1,::1,$host,.local,.internal,.lan"
  export NO_PROXY=$no_proxy
  export all_proxy="socks5://$host:$_DOTFILES_PROXY_PORT"
  export ALL_PROXY=$all_proxy
}

_dotfiles_proxy_host() {
  if (( $+functions[_wsl_proxy_host] )); then
    _wsl_proxy_host
  else
    print -r -- 127.0.0.1
  fi
}

_dotfiles_resolve_host() {
  local host=$1
  if [[ -z $host ]]; then
    (( $+functions[_wsl_clear_cache] )) && _wsl_clear_cache
    host=$(_dotfiles_proxy_host)
  fi
  print -r -- $host
}

if (( _DOTFILES_IN_WSL )); then
  _wsl_default_gw() {
    if (( ${+_DOTFILES_WSL_GW} )); then
      print -r -- $_DOTFILES_WSL_GW
      return
    fi
    typeset -gx _DOTFILES_WSL_GW
    _DOTFILES_WSL_GW=$(ip route show 2>/dev/null | awk '/^default/ {print $3; exit}')
    print -r -- $_DOTFILES_WSL_GW
  }

  _wsl_has_loopback0() {
    if (( ${+_DOTFILES_WSL_LOOPBACK0} )); then
      (( _DOTFILES_WSL_LOOPBACK0 ))
      return
    fi
    typeset -gi _DOTFILES_WSL_LOOPBACK0=0
    ip link show loopback0 >/dev/null 2>&1 && _DOTFILES_WSL_LOOPBACK0=1
    export _DOTFILES_WSL_LOOPBACK0
    (( _DOTFILES_WSL_LOOPBACK0 ))
  }

  _wsl_read_wslconfig_mode() {
    emulate -L zsh -o extendedglob
    local cfg line mode=""
    for cfg in /mnt/c/Users/*/.wslconfig(N); do
      [[ -f $cfg ]] || continue
      case $cfg in
        */All\ Users/*|*/Default*/*|*/Public/*) continue ;;
      esac
      while IFS= read -r line; do
        [[ ${(L)line} == [[:space:]]#networkingmode[[:space:]]#=* ]] || continue
        mode=${line#*=}
        mode=${(L)${mode//[\"\'[:space:]]}}
        break
      done < $cfg
      [[ -n $mode ]] && break
    done
    case $mode in
      mirrored|mirror) print mirrored ;;
      nat) print nat ;;
    esac
  }

  _wsl_is_nat_gw() {
    local gw=$1
    [[ -n $gw && $gw =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]
  }

  # 镜像 -> 127.0.0.1；NAT -> 默认网关。结果缓存到环境，exec zsh 可复用。
  _wsl_proxy_host() {
    if (( ${+_DOTFILES_WSL_PROXY_HOST} )); then
      print -r -- $_DOTFILES_WSL_PROXY_HOST
      return
    fi
    typeset -gx _DOTFILES_WSL_PROXY_HOST=""
    if _wsl_has_loopback0; then
      _DOTFILES_WSL_PROXY_HOST=127.0.0.1
    else
      local gw cfg_mode
      gw=$(_wsl_default_gw)
      if _wsl_is_nat_gw $gw; then
        _DOTFILES_WSL_PROXY_HOST=$gw
      else
        cfg_mode=$(_wsl_read_wslconfig_mode)
        if [[ $cfg_mode == mirrored ]]; then
          _DOTFILES_WSL_PROXY_HOST=127.0.0.1
        elif [[ $cfg_mode == nat && -n $gw ]]; then
          _DOTFILES_WSL_PROXY_HOST=$gw
        fi
      fi
    fi
    print -r -- $_DOTFILES_WSL_PROXY_HOST
  }

  _wsl_clear_cache() {
    unset _DOTFILES_WSL_PROXY_HOST _DOTFILES_WSL_GW _DOTFILES_WSL_LOOPBACK0
  }

  # 仅 WSL 自动设。已有代理变量则跳过。
  if [[ -z ${http_proxy:-} ]]; then
    _wsl_proxy_host_ip=$(_wsl_proxy_host)
    if [[ -n $_wsl_proxy_host_ip ]] && _dotfiles_port_open $_wsl_proxy_host_ip $_DOTFILES_PROXY_PORT 0.2; then
      _dotfiles_set_proxy $_wsl_proxy_host_ip || true
    fi
    unset _wsl_proxy_host_ip
  fi
fi

proxy_off() {
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY \
    all_proxy ALL_PROXY no_proxy NO_PROXY
  print proxy off
}

# 不传 host 时：WSL 按模式选，其它环境用 127.0.0.1
proxy_on() {
  local host
  host=$(_dotfiles_resolve_host $1)
  if [[ -z $host ]]; then
    print 'proxy on FAILED: cannot detect proxy host'
    return 1
  fi
  if ! _dotfiles_port_open $host $_DOTFILES_PROXY_PORT 2; then
    print "proxy on WARNING: $host:$_DOTFILES_PROXY_PORT not reachable (Clash not running or allow-lan off)"
    print "  set proxy anyway? use: proxy_on_force $host"
    return 1
  fi
  _dotfiles_set_proxy $host
  print "proxy on: $http_proxy"
}

proxy_on_force() {
  local host
  host=$(_dotfiles_resolve_host $1)
  if [[ -z $host ]]; then
    print 'proxy on FAILED: cannot detect proxy host'
    return 1
  fi
  _dotfiles_set_proxy $host
  print "proxy on (forced): $http_proxy"
}

proxy_status() {
  if [[ -n $http_proxy ]]; then
    print "proxy ON  -> $http_proxy"
    print "  no_proxy: $no_proxy"
    return
  fi
  print 'proxy OFF'
  local host
  host=$(_dotfiles_proxy_host)
  [[ -n $host ]] || return
  if _dotfiles_port_open $host $_DOTFILES_PROXY_PORT 1; then
    print "  (代理可用 $host:$_DOTFILES_PROXY_PORT，使用 proxy_on 开启)"
  else
    print "  (代理不可用 $host:$_DOTFILES_PROXY_PORT，Clash 未运行或未开 allow-lan)"
  fi
}

proxy_mode() {
  if ! _wsl_in_wsl; then
    print "not in WSL (proxy host defaults to 127.0.0.1:$_DOTFILES_PROXY_PORT)"
    [[ -n $http_proxy ]] && print "  current: proxy ON -> $http_proxy"
    return
  fi
  _wsl_clear_cache
  local gw cfg_mode host has_loopback_ip=0
  gw=$(_wsl_default_gw)
  cfg_mode=$(_wsl_read_wslconfig_mode)
  host=$(_wsl_proxy_host)
  ip -4 addr show lo 2>/dev/null | grep -q '10\.255\.255\.254' && has_loopback_ip=1

  if _wsl_has_loopback0 || [[ $cfg_mode == mirrored ]]; then
    print 'WSL MIRRORED mode (shared network stack, proxy -> 127.0.0.1)'
    [[ -n $cfg_mode ]] && print "  -> .wslconfig networkingMode=$cfg_mode"
    _wsl_has_loopback0 && print '  -> detected: loopback0 interface present'
    [[ -n $gw ]] && print "  (gw=$gw, ignored for mode detection)"
  elif _wsl_is_nat_gw $gw; then
    print "WSL NAT mode (gw=$gw) - proxy via host gateway IP"
    [[ -n $cfg_mode ]] && print "  -> .wslconfig networkingMode=$cfg_mode"
    (( has_loopback_ip )) && print '  -> lo has 10.255.255.254/32 (hostAddressLoopback=true, NAT default, NOT mirrored indicator)'
  elif [[ -z $gw ]]; then
    print 'WSL: no default route'
  else
    print "WSL non-NAT/non-Mirrored mode (gw=$gw) - proxy not auto-enabled"
  fi

  if [[ -n $host ]]; then
    if _dotfiles_port_open $host $_DOTFILES_PROXY_PORT 1; then
      print "  proxy reachable: $host:$_DOTFILES_PROXY_PORT OK"
    else
      print "  proxy NOT reachable: $host:$_DOTFILES_PROXY_PORT (Clash 未运行或未开 allow-lan)"
    fi
  fi
  if [[ -n $http_proxy ]]; then
    print "  current: proxy ON -> $http_proxy"
  else
    print '  current: proxy OFF (直连)'
  fi
}
