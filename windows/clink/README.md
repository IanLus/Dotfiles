# Clink profile

CMD 的 Clink 配置，路径由用户变量 `CLINK_PROFILE` 指向本目录（默认 `%DOTDIR%\windows\clink`）。

## 事先需要什么

`install\all.ps1` **不会**装齐日常工具。跑它之前先具备：

| 依赖 | 用途 | 没有会怎样 |
|------|------|------------|
| 本仓库已克隆 | 脚本按仓库路径写 `DOTDIR` / `CLINK_PROFILE` | 无处可跑 |
| [winget](https://aka.ms/getwinget) | 安装 Clink、fzf、fnm / eza / bat / lua / chafa / starship / lazygit | 对应脚本失败 |
| [Git](https://git-scm.com/download/win) | 克隆 z.lua / clink-fzf / gizmos；可选提供 `gcc` | 上游依赖装不上 |
| PowerShell 7（`pwsh`） | 跑安装脚本 | 可用 Windows PowerShell，但不保证 |
| 开发者模式或管理员 | 创建指向 `C:\Software\clink-plugins\` 的符号链接 | 弹出 UAC；仍失败则需开开发者模式 |

**完整功能还要自己先装**（脚本不代装）：

| 依赖 | 用途 |
|------|------|
| [Neovim](https://neovim.io/) | 别名 `v`、`fzf_rg.editor` |
| Git for Windows 的 `%GIT%\usr\bin` | `elt` / `enable-linux-tools` 把 Unix 工具加进 PATH |
| gcc（Git MinGW 或自备，`CC` 可指定） | 编译 `tools/*.exe`（UTF-8 与 fnm 退出清理）。没有 gcc 时跳过，其余步骤继续 |

winget 包（Clink、`fzf.exe`，以及 `apps.ps1` 的 fnm / eza / bat / Lua / chafa / starship / lazygit）装到 `%SOFTWARE_HOME%\<名>`，逻辑与 `dirx.ps1` 相同：查最新版，过期则询问是否更新，并把 exe 所在目录写入用户 PATH（已有则跳过）。`clink-plugins` 里的 z.lua / clink-fzf / clink-gizmos 只 `git pull`。

可选环境变量：`DOTDIR`、`CLINK_PROFILE`、`CLINK_SOFTWARE_HOME`（默认 `C:\Software\clink-plugins`）、`SOFTWARE_HOME`（默认 `C:\Software`）、`Z_LUA_HOME`、`GIT`、`CC`。未设置时 `all.ps1` 会补上 `DOTDIR` 和 `CLINK_PROFILE`。winget 装 Clink → `C:\Software\clink`，装 `fzf.exe` → `C:\Software\fzf`，其余见 `apps.ps1`。

不要改 `HKCU\Software\Microsoft\Command Processor\AutoRun`，Clink 安装程序占用该项。

## 一键安装

机器上可以还没有 Clink：

```powershell
pwsh -File "$HOME\Documents\dotfiles\windows\clink\install\all.ps1"
```

已有 `DOTDIR` 时：

```powershell
pwsh -File "%DOTDIR%\windows\clink\install\all.ps1"
```

顺序：`DOTDIR` / `CLINK_PROFILE` → winget 装 Clink → gcc 编 `tools/*.exe` → `clink set` 与 starship 提示符 → apps（fnm / eza / bat / lua / chafa / starship / lazygit）→ z.lua → clink-fzf + fzf.exe → gizmos → dirx → profile 加入用户 PATH。

代理：已有 `HTTPS_PROXY` / `HTTP_PROXY` / `ALL_PROXY` 则直接用；否则询问，回车默认 `http://127.0.0.1:7890`。`-NoProxy` 关闭；`-Proxy` 指定。`-Minimal` 只链 `fzf.lua`。

单步：`install\clink.ps1`、`tools.ps1`、`apps.ps1`、`z.ps1`、`fzf.ps1`、`gizmos.ps1`、`dirx.ps1`。`apps.ps1 -Name fnm,eza` 只处理列出的包。

`clink_settings` 和 `tools/*.exe` 由脚本生成，不入库。

## 目录

Clink 只自动加载 profile **根目录**的 `*.lua`，子目录由 `init.lua` 拉入。

```
clink/
  init.lua                 # 加载 aliases/ 与 functions/
  README.md
  install/
    all.ps1                # 从零一键
    common.ps1             # 安装脚本共用
    clink.ps1              # Clink、环境变量、clink set、starship
    tools.ps1              # 编译 tools/*.exe
    apps.ps1               # fnm/eza/bat/lua/chafa/starship/lazygit → C:\Software\<名>
    z.ps1                  # z.lua / z.cmd
    fzf.ps1                # clink-fzf 插件 + fzf.exe → C:\Software\fzf
    gizmos.ps1             # clink-gizmos / tilde_autoexpand
    dirx.ps1               # dirx.exe → C:\Software\dirx
  tools/                   # 只入库 .c
  fzf-preview.cmd
  fzf-list-files.cmd
  fzf-list-dirs.cmd
  aliases/init.lua         # doskey
  functions/
    utf8_console.lua
    lua_commands.lua       # Lua 命令着色 / 补全
    fzf_env.lua
    fzf_bindings.lua       # Tab 用 fzf；/ 连续补全
    envvar_complete.lua    # %VAR% 补全
    fnm.lua
    unix_tools.lua         # elt / dlt
    fs.lua                 # mkcd / rm
    which.lua
    proxy.lua
```

根目录的 `z.lua`、`fzf.lua`、`tilde_autoexpand.lua` 等是安装脚本做的符号链接，不入库。

## 快捷键与命令

Tab / Ctrl+Space：fzf 筛选补全。窗口里 `/` 接受并继续（目录进下级，文件加空格后补下一参数），Enter 只接受。`**` 仍为递归。Ctrl+T 选文件，Ctrl+R 历史，Alt+C 进目录，Alt+Shift+/ 列出已绑定命令，Ctrl+/ 切换预览。

```cmd
mkcd mydir
rm file.txt
rm -r dir
which spr
spr
gpr
cpr
elt
dlt
```

不要再创建 `%LocalAppData%\clink\starship.lua`。若 `starship.exe` 不在 PATH：`clink set starship.exepath "完整路径\starship.exe"`。
