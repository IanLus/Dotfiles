#!/hint/zsh
# pacman / paru 补全候选的 fzf-tab 预览。
# 由 fzf-tab 的预览进程 source 进来，此时已经有：
#   word     - 当前聚焦候选（包名 / 仓库名 / 组名 / 文件路径）
#   group    - 补全组名，形如 "[packages]"
#   words    - 触发补全时命令行上的所有词
#   realpath - 候选是文件时的绝对路径
#
# 注意：不能沿用 lessfilter 里的 cat —— pacman 的候选根本不是文件，
# realpath 是空的，`lessfilter.sh ''` 会直接报 "cat: ''"。

_dotfiles_preview_file() {
  local f=${1:-}
  if [[ -z $f || ! -e $f ]]; then
    print -r -- "（不是文件：${f:-空}）"
    return 0
  fi
  "$DOTDIR/less/lessfilter.sh" ${(q)f}
}

# 缓存目录随本地库 / 同步库的 mtime 变化，-Sy 之后自动失效
_dotfiles_pacman_cache_dir() {
  local -A st
  local p stamp=''
  for p in /var/lib/pacman/local /var/lib/pacman/sync; do
    if zmodload -F zsh/stat b:zstat 2>/dev/null && zstat -H st -- $p 2>/dev/null; then
      stamp+=$st[mtime]
    else
      stamp+=0
    fi
  done
  print -r -- "${TMPDIR:-/tmp}/fzf-tab-pacman-${USER}-$stamp"
}

# 跑 pacman，stdout 空或退出码非 0 时返回 1，让上层去挑回退方案
_dotfiles_pacman_run() {
  local out
  out=$(command pacman --color=always "$@" 2>/dev/null) || return 1
  [[ -n $out ]] || return 1
  print -r -- "$out"
}

_dotfiles_preview_pacman() {
  emulate -L zsh
  setopt no_aliases

  local w=${(Q)${word:-}}
  local g=${${group:-}#\[}
  g=${g%\]}
  # realpath 是 fzf-tab 拼好的完整路径（目录 + 候选），不是单纯的目录
  local target=${(Q)${realpath:-}}
  [[ -n $target ]] || target=$w
  # 相对路径在预览进程里的 cwd 可能对不上，转成绝对路径再查
  [[ $target == /* ]] || [[ ! -e $target ]] || target=${target:A}

  # 候选是 pacman 自己的选项（[option] 组），或者正在补的就是个选项，不用查包信息
  [[ $g == option || $w == -* ]] && return 0

  # 当前正在补全的词。仓库前缀（core/xx）被 compset 吃进 IPREFIX，候选里不再带出来。
  local cur=${words[-1]:-}
  local repo_prefix=''
  [[ $cur == */* ]] && repo_prefix=${cur%/*}/

  # 已经敲下的选项。不要把选项后面的参数（包名等）误判成选项。
  local -a opts
  (( $#words > 2 )) && opts=( ${(M)${words[2,-2]}:#-*} )

  local o sh='' lgn=' '
  for o in "${opts[@]}"; do
    if [[ $o == --* ]]; then
      lgn+="${o#--} "
    else
      sh+=${o#-}
    fi
  done
  lgn+=' '

  # 操作。Q 要先判（-Qs 里同时有 S 和 Q）。
  local op=''
  if [[ $lgn == *' query '* || $sh == *Q* ]]; then
    op=Q
  elif [[ $lgn == *' sync '* || $sh == *S* ]]; then
    op=S
  elif [[ $lgn == *' files '* || $sh == *F* ]]; then
    op=F
  elif [[ $lgn == *' remove '* || $sh == *R* ]]; then
    op=R
  elif [[ $lgn == *' upgrade '* || $sh == *U* ]]; then
    op=U
  elif [[ $lgn == *' deptest '* || $sh == *T* ]]; then
    op=T
  elif [[ $lgn == *' database '* || $sh == *D* ]]; then
    op=D
  fi

  # 修饰符：短选项里剩下的字母 + 等价的长选项（别重复添加）
  local mods=${sh//[A-Z]/}
  [[ $lgn == *' info '* && $mods != *i* ]] && mods+=i
  [[ $lgn == *' list '* && $mods != *l* ]] && mods+=l
  [[ $lgn == *' groups '* && $mods != *g* ]] && mods+=g
  [[ $lgn == *' owns '* && $mods != *o* ]] && mods+=o
  [[ $lgn == *' changelog '* && $mods != *c* ]] && mods+=c
  [[ $lgn == *' check '* && $mods != *k* ]] && mods+=k
  [[ $lgn == *' file '* && $mods != *p* ]] && mods+=p

  local -a c
  case $op in
    S)
      if [[ $w == */ || $g == 'package repo' ]]; then
        # 候选是仓库名（core/），列出仓库里的包
        c=( -Sl -- ${w%/} )
      elif [[ $mods == *g* ]]; then
        # -Sg：组名 → 组成员
        c=( -Sg -- $w )
      elif [[ $mods == *l* ]]; then
        c=( -Sl -- ${w%/} )
      else
        # -S / -Si / -Sw ...：看仓库包信息
        c=( -Si -- $repo_prefix$w )
      fi
      ;;
    Q)
      if [[ $mods == *g* ]]; then
        c=( -Qg -- $w )
      elif [[ $mods == *o* ]]; then
        # -Qo：反查文件属于哪个包
        [[ -n $target ]] || { _dotfiles_preview_file ''; return 0 }
        c=( -Qo -- $target )
      elif [[ $mods == *p* ]]; then
        # -Qp：查询本地包文件
        [[ $target == *.pkg.tar* ]] || { _dotfiles_preview_file $target; return 0 }
        c=( -Qip -- $target )
      elif [[ $mods == *l* ]]; then
        c=( -Ql -- $w )
      elif [[ $mods == *k* ]]; then
        c=( -Qk -- $w )
      elif [[ $mods == *c* ]]; then
        c=( -Qc -- $w )
      else
        c=( -Qi -- $w )
      fi
      ;;
    F)
      if [[ $mods == *l* ]]; then
        c=( -Fl -- $w )
      elif [[ -n $target && -e $target ]]; then
        # 文件数据库里反查这个文件
        c=( -F -- $target )
      else
        return 0
      fi
      ;;
    U)
      if [[ $target == *.pkg.tar* ]]; then
        c=( -Qip -- $target )
      else
        _dotfiles_preview_file $target
        return 0
      fi
      ;;
    R|D|T)
      c=( -Qi -- $w )
      ;;
    *)
      # 命令位、选项位，或者没有走 -S/-Q/-F/-U 的路径参数（--config、--root…）
      if [[ -f $target ]]; then
        _dotfiles_preview_file $target
      fi
      return 0
      ;;
  esac

  [[ -n $w ]] || return 0

  # 补全组名已经说明了语义：--ignoregroup 这种走 [package group]，
  # 光看选项字母分不出来，交给组名兜底。
  if [[ $g == *group* ]]; then
    if [[ $op == Q ]]; then
      c=( -Qg -- $w )
    else
      c=( -Sg -- $w )
    fi
  fi

  local cache_dir=$(_dotfiles_pacman_cache_dir)
  local key=${(j:_:)c}
  key=${key//[^A-Za-z0-9._-]/_}
  key=${key[1,150]}
  local cache_file=$cache_dir/$key

  if [[ -r $cache_file ]]; then
    command cat -- $cache_file
    return 0
  fi

  local out=''
  out=$(_dotfiles_pacman_run "${c[@]}")

  # 本地库查不到就回退：-Qi → 去仓库查；-Si → AUR 包问 paru 之类；
  # -Ql/-Fl → 元包没有文件列表，退回看包信息。
  if [[ -z $out ]]; then
    case $c[1] in
      -Qi)
        out=$(_dotfiles_pacman_run -Si -- $repo_prefix$w)
        ;;
      -Si)
        local helper
        for helper in ${words:#(#b)(pacman|pacman-conf)}; do
          [[ $helper == (paru|yay|pikaur) ]] || continue
          command -v $helper >/dev/null 2>&1 || continue
          out=$(timeout 10 $helper --color=always -Si -- $repo_prefix$w 2>/dev/null)
          [[ -n $out ]] && break
        done
        ;;
      -Ql|-Fl)
        local info
        info=$(_dotfiles_pacman_run -Qi -- $w)
        if [[ -n $info ]]; then
          out="「$w」没有文件列表，下面是包信息：

$info"
        fi
        ;;
    esac
  fi

  # 还是空就把 pacman 的报错原样给用户看，别留一个空预览（报错不进缓存）
  local cacheable=1
  if [[ -z $out ]]; then
    out=$(command pacman --color=always "${c[@]}" 2>&1)
    cacheable=0
  fi

  # 只缓存有内容的正常结果，免得把一次空结果 / 报错永久钉死
  if (( cacheable )) && [[ -n $out ]]; then
    if [[ ! -d $cache_dir ]]; then
      command mkdir -p -- $cache_dir 2>/dev/null
      # 同步库变了就是新目录，顺手清掉旧的
      setopt local_options extended_glob
      local old
      for old in ${cache_dir:h}/fzf-tab-pacman-${USER}-*(/N); do
        [[ $old == $cache_dir ]] || command rm -rf -- $old
      done
    fi
    [[ -d $cache_dir ]] && print -r -- "$out" >| $cache_file 2>/dev/null
  fi

  print -r -- "$out"
}
