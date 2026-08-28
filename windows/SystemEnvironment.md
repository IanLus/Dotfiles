# 系统环境变量

不指明情况下默认为**用户变量**。登录时按步加载，后一步可以引用前一步已经定下的值（[The Old New Thing](https://devblogs.microsoft.com/oldnewthing/20231212-00/?p=109137)）：

1. 系统 `REG_SZ` → 系统 `REG_EXPAND_SZ`
2. 核心用户变量（`USERPROFILE`、`LOCALAPPDATA` 等）
3. 用户 `REG_SZ` → 用户 `REG_EXPAND_SZ`

因此：**不可展开（`REG_SZ`）先于可展开（`REG_EXPAND_SZ`）**。用户级 `REG_EXPAND_SZ` 能读到用户级 `REG_SZ`（以及系统变量 / `USERPROFILE`），但不能依赖**同一步**里另一个 `REG_EXPAND_SZ`（结果未指定）。

含 `%…%` 的值必须是 **REG_EXPAND_SZ**。`setx` 和 `[Environment]::SetEnvironmentVariable` 会写成 **REG_SZ**，`%VAR%` 就不会展开。安装脚本对 `Path` 和带 `%` 的值按 REG_EXPAND_SZ 写。

## 手动添加部分

### 配置仓库路径

```cmd
// 用户变量，绝对路径字面量（REG_SZ）——供后面的 REG_EXPAND_SZ 引用
DOTDIR=C:\Users\<user>\Documents\dotfiles
```

安装脚本在未设置时写入用户级绝对路径（REG_SZ），不写成 `%USERPROFILE%\...`。

### 默认编辑器

```cmd
// 系统变量
EDITOR=nvim
```

### Git 相关

```cmd
// 系统变量
GIT=C:\Program Files\Git

// 用户变量
GITHUB_TOKEN=ghp_***
```

### Komorebi 配置目录

```cmd
// 用户变量，REG_EXPAND_SZ。DOTDIR 是用户 REG_SZ，登录时可以展开。
KOMOREBI_CONFIG_HOME=%DOTDIR%\windows\komorebi
```

### Miniforge 路径

```cmd
// 系统变量
MINIFORGE=C:\Software\miniforge3
```

### fnm 版本文件查找策略（与 WSL 对齐；Clink / pwsh 共用）

```cmd
FNM_VERSION_FILE_STRATEGY=recursive
```

fnm 不会在 shell 退出时删除 `FNM_MULTISHELL_PATH`。pwsh / Clink 会启动 `tools/fnm_multishell_cleanup.exe`，等本进程结束后再删掉该符号链接。exe 不入库，由安装脚本编译：

```powershell
pwsh -File "%DOTDIR%\windows\clink\install\tools.ps1"
```

### Starship 配置文件

```cmd
// 用户变量，REG_EXPAND_SZ
STARSHIP_CONFIG=%DOTDIR%\windows\starship\starship.toml
```

### 默认C语言编译器

```cmd
// 系统变量
CC=gcc
```

### Ollama

```cmd
OLLAMA_HOST=0.0.0.0:11434
OLLAMA_ORIGINS=*
```

### Java

```cmd
// JAVA8 为用户 REG_SZ，JAVA_HOME 为用户 REG_EXPAND_SZ，登录时可以展开。
JAVA_HOME=%JAVA8%
JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF-8
JAVA8=C:\Program Files\Java\jdk1.8.0_202
```

### Clink 配置目录

`DOTDIR` 是用户级 `REG_SZ` 字面量，所以 `CLINK_PROFILE` 写成 `%DOTDIR%\windows\clink`（用户级 `REG_EXPAND_SZ`）在登录时会展开。

```cmd
// 用户变量，REG_EXPAND_SZ
CLINK_PROFILE=%DOTDIR%\windows\clink
```

安装脚本在未设置时这样写；若已有 `%…%` 却是 `REG_SZ` 会改成 `REG_EXPAND_SZ`。

`all.ps1` 会把 **`%CLINK_PROFILE%`** 写入用户 `PATH`（已有该变量或展开后相同的绝对路径则改成 / 保留这一项）。`Path` 与 `CLINK_PROFILE` 同属用户 `REG_EXPAND_SZ` 那一步，互相引用未指定；实现里往往按名字顺序，`CLINK_PROFILE` 在 `Path` 之前，所以通常能展开。系统级 `CLINK_DIR`、用户 `REG_SZ` 的 `PNPM_HOME`、以及 `LOCALAPPDATA` 都可以安全引用。

### CMD / 控制台 UTF-8

中文 Windows 默认代码页是 **936（GBK）**。不要用 `chcp 65001` 切（Windows Terminal 里会话内首次切换会复位视口）。

Clink 启动时通过 `tools/set_console_utf8.exe` 调用 `SetConsoleCP` / `SetConsoleOutputCP`（与 pwsh 的 `[Console]::OutputEncoding` 同类）。源码：`windows/clink/tools/set_console_utf8.c`。exe 不入库，与 `fnm_multishell_cleanup.exe` 一并：

```powershell
pwsh -File "%DOTDIR%\windows\clink\install\tools.ps1"
```

系统级方案（改 ACP，影响所有非 Unicode 程序）：设置 → 时间和语言 → 管理语言设置 → 更改系统区域设置 → **Beta: 使用 Unicode UTF-8**。

不要改 `HKCU\Software\Microsoft\Command Processor\AutoRun`：该项已被 Clink 占用。

### Clink 上游仓库（不纳入 dotfiles）

Clink 本体装到 `C:\Software\clink`。第三方仓库统一放在 `C:\Software\clink-plugins\`（可用 `CLINK_SOFTWARE_HOME` 覆盖根目录）：

| 脚本 | 上游路径 |
|------|----------|
| `install\z.ps1` | `C:\Software\clink-plugins\z.lua`（`Z_LUA_HOME` 可覆盖） |
| `install\fzf.ps1` | `C:\Software\clink-plugins\clink-fzf` |
| `install\gizmos.ps1` | `C:\Software\clink-plugins\clink-gizmos` |

新机器（可以还没有 Clink）一次装完：

```powershell
pwsh -File "%DOTDIR%\windows\clink\install\all.ps1"
```

会写入用户级 `DOTDIR`（绝对路径，`REG_SZ`）和 `CLINK_PROFILE=%DOTDIR%\windows\clink`（`REG_EXPAND_SZ`；若未设置），把 `%CLINK_PROFILE%` 加入用户 PATH，安装 Clink、编译 `tools/*.exe`、应用 `clink set`，并用 winget 把 fnm / eza / bat / lua / chafa / starship / lazygit 装到 `C:\Software\<名>`，以及安装上游依赖。也可在 `install\` 下单独跑对应脚本（`apps.ps1` 可带 `-Name fnm`）。

## 自动添加部分

安装脚本（`windows\clink\install\`）只写**用户**环境，不写系统变量。未设置才补；已有则保留（PATH 按目录去重）。

| 变量 | 脚本 | 写入 |
|------|------|------|
| `DOTDIR` | `clink.ps1` / `all.ps1`（`Ensure-DotDirAndClinkProfile`） | 仓库根绝对路径，`REG_SZ` |
| `CLINK_PROFILE` | 同上 | `%DOTDIR%\windows\clink`，`REG_EXPAND_SZ`；若已有 `%…%` 却是 `REG_SZ` 则改类型 |
| 用户 `Path` | `all.ps1` | 追加 `%CLINK_PROFILE%`（已有该字面量或展开后同一目录则跳过 / 改成变量形式） |
| 用户 `Path` | `clink.ps1`、`apps.ps1`、`dirx.ps1` 等 | 追加 `clink.exe` 与 winget/dirx 工具所在目录的绝对路径（已有则跳过） |

跑脚本时还会改**当前进程**（不进注册表）：`CLINK_PROFILE` 指到本仓库；未加 `-NoProxy` 时设置 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY`。新开终端才吃到注册表里的值。

`EDITOR`、`GIT`、`MINIFORGE`、`CC`、`STARSHIP_CONFIG`、`KOMOREBI_CONFIG_HOME` 等由本文件其它节手动配置，安装脚本不写。

### pnpm 路径

```cmd
PNPM_HOME=C:\Users\witty\AppData\Local\pnpm （pnpm setup）
```

### Clink 安装目录

```cmd
CLINK_DIR=C:\Software\clink （Clink 安装程序写入的系统变量）
```
