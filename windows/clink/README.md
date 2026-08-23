# Clink profile

这是 CMD 的 **Clink 配置**（`CLINK_PROFILE`），不是 Clink 程序本身。默认路径：`%DOTDIR%\windows\clink`。

Clink 只自动加载本目录根上的 `*.lua`。`aliases/`、`functions/` 由 `init.lua` 拉入。根上的 `z.lua`、`fzf.lua`、`tilde_autoexpand.lua` 等是安装脚本做的符号链接，不入库。

## 三层路径

默认根目录是 `C:\Software`，可用 `SOFTWARE_HOME` 改。插件根目录默认为 `%SOFTWARE_HOME%\clink-plugins`，可用 `CLINK_SOFTWARE_HOME` 改。

| 层 | 是什么 | 默认位置 |
|----|--------|----------|
| 程序 | Clink、`fzf.exe` 等 winget / 预编译工具 | `%SOFTWARE_HOME%\clink`、`%SOFTWARE_HOME%\fzf` … |
| 插件仓库 | z.lua、clink-fzf、clink-gizmos | `%SOFTWARE_HOME%\clink-plugins\<仓库名>` |
| 配置 | 本目录 | `%DOTDIR%\windows\clink` |

不要和 `fzf.exe` 搞混：`clink-plugins\clink-fzf` 是 Clink 的 fzf 补全插件；二进制在 `%SOFTWARE_HOME%\fzf`。

UTF-8、`CLINK_DIR`、AutoRun 等环境说明见 [SystemEnvironment.md](../SystemEnvironment.md)。不要改 `HKCU\Software\Microsoft\Command Processor\AutoRun`，那是 Clink 安装程序的。

## 一键安装

机器上可以还没有 Clink。先具备：本仓库、[winget](https://aka.ms/getwinget)、[Git](https://git-scm.com/download/win)、PowerShell 7（`pwsh`），以及**开发者模式或管理员**（给 `clink-plugins` 做符号链接；否则会弹 UAC）。

```powershell
pwsh -File "$HOME\Documents\dotfiles\windows\clink\install\all.ps1"
```

已有 `DOTDIR` 时：

```powershell
pwsh -File "$env:DOTDIR\windows\clink\install\all.ps1"
```

未设置时会补上 `DOTDIR` 和 `CLINK_PROFILE=%DOTDIR%\windows\clink`。装完把 profile 加入用户 PATH（已有则跳过）。**新开一个终端**后再用。

代理：已有 `HTTPS_PROXY` / `HTTP_PROXY` / `ALL_PROXY` 则直接用；否则询问，回车默认 `http://127.0.0.1:7890`。`-NoProxy` 关闭；`-Proxy` 指定。`-Minimal` 只链 `fzf.lua`。

顺序：`clink.ps1` → `tools.ps1` → `apps.ps1` → `z.ps1` → `fzf.ps1` → `gizmos.ps1` → `dirx.ps1`。也可在 `install\` 下单独跑。`apps.ps1 -Name fnm,eza` 只处理列出的包。

`clink_settings` 和 `tools/*.exe` 由脚本生成，不入库。不要再创建 `%LocalAppData%\clink\starship.lua`。

## 脚本会装什么

winget 包（以及 dirx 的 GitHub release）查最新版，过期则询问是否更新，并把 **exe 所在目录** 写入用户 PATH（已有则跳过）。插件仓库只 `git pull`。

| 脚本 | 来源 | 装到 |
|------|------|------|
| `clink.ps1` | winget `chrisant996.Clink` | `%SOFTWARE_HOME%\clink` |
| `apps.ps1` | winget：fnm、eza、bat、Lua、chafa、starship、lazygit | `%SOFTWARE_HOME%\<名>`（Lua 的 WiX 安装器不支持 `--location`，落到默认目录，PATH 仍加 `lua.exe` 所在处；starship 的 `--location` 无效，安装前会询问是否继续） |
| `fzf.ps1` | git `clink-fzf`；winget `junegunn.fzf` | `%SOFTWARE_HOME%\clink-plugins\clink-fzf`；`%SOFTWARE_HOME%\fzf` |
| `z.ps1` | git `z.lua` | `%SOFTWARE_HOME%\clink-plugins\z.lua`（`Z_LUA_HOME` 可覆盖） |
| `gizmos.ps1` | git `clink-gizmos` | `%SOFTWARE_HOME%\clink-plugins\clink-gizmos` |
| `dirx.ps1` | GitHub release | `%SOFTWARE_HOME%\dirx` |
| `tools.ps1` | 本仓库 `.c` 用 gcc 编 | `tools\*.exe`（没有 gcc 则跳过，其余步骤继续） |

其它可选变量：`GIT`、`CC`。

## 脚本不装

| 依赖 | 用途 |
|------|------|
| [Neovim](https://neovim.io/) | 别名 `v`、`fzf_rg.editor` |
| Git for Windows 的 `%GIT%\usr\bin` | `elt` / `enable-linux-tools` 把 Unix 工具加进 PATH |
| gcc（Git MinGW 或自备，`CC` 可指定） | 编译 `tools/*.exe` |

## 目录

```
clink/
  init.lua                 # 加载 aliases/ 与 functions/
  README.md
  install/
    all.ps1
    common.ps1
    clink.ps1
    tools.ps1
    apps.ps1
    z.ps1
    fzf.ps1
    gizmos.ps1
    dirx.ps1
  tools/                   # 只入库 .c
  fzf-preview.cmd
  fzf-list-files.cmd
  fzf-list-dirs.cmd
  aliases/init.lua
  functions/
    utf8_console.lua
    lua_commands.lua
    fzf_env.lua
    fzf_bindings.lua       # Tab 用 fzf；/ 连续补全
    envvar_complete.lua    # %VAR% 补全
    fnm.lua
    unix_tools.lua         # elt / dlt
    fs.lua                 # mkcd / rm
    which.lua
    proxy.lua
```

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

若 `starship.exe` 不在 PATH：`clink set starship.exepath "完整路径\starship.exe"`。
