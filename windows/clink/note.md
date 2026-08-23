# clink安装与配置

## Install

```cmd
winget install --id=chrisant996.Clink -e
```

## 让 clink 使用 starship 提示符

安装 Starship 后执行（会写入 `clink.customprompt`，加载 Clink 自带的 `starship.clinkprompt`）：

```cmd
clink config prompt use starship
```

不要再创建 `%LocalAppData%\clink\starship.lua`；旧写法与 `.clinkprompt` 重复，可能造成提示符异常。

若 `starship.exe` 不在 `PATH` 中：

```cmd
clink set starship.exepath "完整路径\starship.exe"
```

## clink切换快捷键风格为bash命令

```cmd
clink set clink.default_bindings bash
```

## 启动clink自动建议 (Auto-Suggestions)（默认）

```cmd
clink set autosuggest.enable true
```

## 让clink根据历史命令生成自动建议规则（默认）

```cmd
clink set autosuggest.strategy match_prev_cmd history completion
```

## 让clink在命令行行内显示建议

```cmd
clink set autosuggest.inline true
```

## 关闭启动cmd时的clink信息输出

```cmd
clink set clink.logo none
```

## 一键安装上游依赖（新机器）

在已设置 `CLINK_PROFILE`（即 `%DOTDIR%\windows\clink`）后执行一次即可，不必逐个跑 `install\` 下的脚本：

```powershell
pwsh -File "%CLINK_PROFILE%\install\all.ps1"
```

顺序：`z.lua` → `clink-fzf` → `clink-gizmos` → `dirx`，并把 `%CLINK_PROFILE%` 加入用户 PATH。已有 `HTTPS_PROXY` / `HTTP_PROXY` / `ALL_PROXY` 则直接用，不再询问；否则询问代理地址，直接回车用 `http://127.0.0.1:7890`。无代理加 `-NoProxy`；非交互指定代理用 `-Proxy`。仅核心 fzf 脚本加 `-Minimal`。

## 自定义脚本（`%CLINK_PROFILE%`，即 `%DOTDIR%\windows\clink`）

别名与函数分目录存放；根目录的 `load_custom.lua` 负责加载（Clink 不会递归扫描子目录）。

```
clink/
  load_custom.lua          # 加载器
  install/                 # 上游安装脚本
    all.ps1                # 一键：z + clink-fzf + gizmos + dirx
    z.ps1                  # z.lua / z.cmd（C:\Software\clink\z.lua）
    clink-fzf.ps1          # fzf 集成（C:\Software\clink\fzf）
    clink-gizmos.ps1
    dirx.ps1               # dirx.exe（C:\Software）
  fzf-preview.cmd          # fzf 预览脚本（目录/图片/文本）
  aliases/
    aliases.lua            # doskey 别名（含 spr/gpr/cpr/elt/dlt）
  functions/
    register_cmds.lua      # Lua 命令着色/补全注册
    fnm.lua                # fnm env --use-on-cd --version-file-strategy=recursive + onbeginedit；退出时删掉本会话 multishell 链接
    path_linux.lua         # enable-linux-tools / disable-linux-tools
    utils.lua              # mkcd / which / rm
    proxy.lua              # proxy_on / proxy_off / proxy_status
    fzf_env.lua            # FZF_* 预览环境变量（仅 cmd/clink）
    fzf_bindings.lua       # Alt+Shift+/ = fzf_bindings；Tab/Ctrl+Space = fzf（预填当前词）；Alt+B 还原 backward-word
```

`z.lua` / `z.cmd` 为上游第三方脚本（~83KB），**不提交到 dotfiles**；由 `install\z.ps1` 链接到 `%Z_LUA_HOME%`（默认 `C:\Software\clink\z.lua`）。

```cmd
mkcd mydir
rm file.txt
rm -r dir
rm -rf dir
which spr
which set-proxy
proxy_on
proxy_on http://127.0.0.1:7890
spr
proxy_status
gpr
proxy_off
cpr
elt
dlt
```

## 配置 `z.lua`

1. 将 `%CLINK_PROFILE%` 加入用户 `PATH`（让 `z.cmd` 可在任意目录调用）
2. 克隆上游（或由脚本代劳）：

```powershell
pwsh -File "%CLINK_PROFILE%\install\z.ps1"
```

默认克隆到 `C:\Software\clink\z.lua`，并在 `%CLINK_PROFILE%` 下创建 `z.lua`、`z.cmd` 符号链接。可选环境变量 `Z_LUA_HOME` 覆盖上游路径。安装脚本默认经 `http://127.0.0.1:7890` 代理拉取；`-NoProxy` 禁用。

WSL/zsh 侧仍由 zinit 管理 `skywind3000/z.lua`，与 Windows 无关。

## 配置 clink-fzf（Ctrl+T、`**` Tab 等）

1. 确保 `fzf.exe` 在 `PATH` 中（或 `clink set fzf.exe_location <path>`）
2. 安装并链接上游文件：

```powershell
pwsh -File "%CLINK_PROFILE%\install\clink-fzf.ps1"
```

默认克隆到 `C:\Software\clink\fzf`，并在 profile 下链接 `fzf.lua` 等文件（符号链接）。默认经 `http://127.0.0.1:7890` 代理拉取；`-NoProxy` 禁用。仅核心：

```powershell
pwsh -File "%CLINK_PROFILE%\install\clink-fzf.ps1" -Minimal
```

3. 脚本会启用 `fzf.default_bindings` 与 `fzf_git.default_bindings`。

常用键：`Ctrl+T` 选文件，`Tab` / `Ctrl+Space` 用 fzf 筛选补全（`**` 仍为递归），`Ctrl+R` 历史，`Alt+C` 进子目录，`Alt+Shift+/`（`\e?`）列出并执行已绑定命令（覆盖 clink-fzf 默认的 `Alt+B`，以及 Clink 默认的 `clink-what-is`）。

### fzf 预览配置

**`clink_settings`**：`fzf.height`、`fzf_rg.show_preview`、`fzf_rg.editor` 等。

**`functions/fzf_env.lua`**：`FZF_CTRL_T_OPTS`、`FZF_COMPLETION_OPTS`（Ctrl+T 与 `**` Tab 共用预览）、`FZF_GIT_CAT` 等。若已安装 dirx，会自动设置 `FZF_CTRL_T_COMMAND` / `FZF_ALT_C_COMMAND` 为 `--bare-relative`（菜单与回显均为相对路径，与 WSL 一致）。

**dirx（相对路径列表）**：

```powershell
pwsh -File "%CLINK_PROFILE%\install\dirx.ps1"
```

默认安装到 `C:\Software\dirx.exe` 并将 `C:\Software` 加入用户 PATH（与 clink 上游仓库分离）。文档见 [clink-fzf FZF_CTRL_T_COMMAND](https://github.com/chrisant996/clink-fzf/blob/master/fzf.lua)、[dirx --bare-relative](https://github.com/chrisant996/dirx#options)。

**`fzf-preview.cmd`**：目录 → `eza --git -ahl --color=always --icons=always`（同 `less/lessfilter.sh`），图片 → chafa，文本 → bat。预览窗 `Ctrl+/` 切换。

## 配置 tilde_autoexpand（`~` 展开为 HOME）

```powershell
pwsh -File "%CLINK_PROFILE%\install\clink-gizmos.ps1"
```

默认克隆到 `C:\Software\clink\gizmos` 并链接 `tilde_autoexpand.lua`（符号链接）。

## 启用快捷键 `ctrl` + `d` 退出

```cmd
clink set cmd.ctrld_exits true
```
