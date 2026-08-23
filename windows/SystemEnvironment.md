# 系统环境变量

不指明情况下默认为用户变量

## 手动添加部分

### 配置仓库路径

```cmd
// 系统变量
DOTDIR=%USERPROFILE%\Documents\dotfiles
```

### 默认编辑器

```cmd
// 系统变量
EDITOR=nvim
```

### Git 相关

```cmd
GIT=C:\Program Files\Git
GITHUB_TOKEN=ghp_***
```

### Komorebi 配置目录

```cmd
KOMOREBI_CONFIG_HOME=%DOTDIR%\windows\komorebi
```

### Miniforge 路径

```cmd
MINIFORGE=C:\Software\miniforge3
```

### fnm 版本文件查找策略（与 WSL 对齐；Clink / pwsh 共用）

```cmd
FNM_VERSION_FILE_STRATEGY=recursive
```

fnm 不会在 shell 退出时删除 `FNM_MULTISHELL_PATH`。pwsh / Clink 会启动 `tools/fnm_multishell_cleanup.exe`，等本进程结束后再删掉该符号链接。重新编译：

```cmd
gcc -O2 -s -mwindows -o %CLINK_PROFILE%\tools\fnm_multishell_cleanup.exe %CLINK_PROFILE%\tools\fnm_multishell_cleanup.c -lshell32
```

### Starship 配置文件

```cmd
STARSHIP_CONFIG=%DOTDIR%\windows\starship\starship.toml
```

### 默认C语言编译器

```cmd
CC=gcc
```

### Ollama

```cmd
OLLAMA_HOST=0.0.0.0:11434
OLLAMA_ORIGINS=*
```

### Java

```cmd
JAVA_HOME=%JAVA8%
JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF-8
JAVA8=C:\Program Files\Java\jdk1.8.0_202
```

### Clink 配置目录

```cmd
CLINK_PROFILE=%DOTDIR%\windows\clink
```

将 `%CLINK_PROFILE%` 加入用户 `PATH`，以便全局调用 `z.cmd`（doskey 别名 `zb`/`zf` 等依赖此项）。

### CMD / 控制台 UTF-8

中文 Windows 默认代码页是 **936（GBK）**。不要用 `chcp 65001` 切（Windows Terminal 里会话内首次切换会复位视口）。

Clink 启动时通过 `tools/set_console_utf8.exe` 调用 `SetConsoleCP` / `SetConsoleOutputCP`（与 pwsh 的 `[Console]::OutputEncoding` 同类）。源码：`windows/clink/tools/set_console_utf8.c`。重新编译：

```cmd
gcc -O2 -s -o %CLINK_PROFILE%\tools\set_console_utf8.exe %CLINK_PROFILE%\tools\set_console_utf8.c
```

系统级方案（改 ACP，影响所有非 Unicode 程序）：设置 → 时间和语言 → 管理语言设置 → 更改系统区域设置 → **Beta: 使用 Unicode UTF-8**。

不要改 `HKCU\Software\Microsoft\Command Processor\AutoRun`：该项已被 Clink 占用。

### Clink 上游仓库（不纳入 dotfiles）

所有 Clink 第三方仓库统一放在 `C:\Software\clink\`（可用 `CLINK_SOFTWARE_HOME` 覆盖根目录）：

| 脚本 | 上游路径 |
|------|----------|
| `install\z.ps1` | `C:\Software\clink\z.lua`（`Z_LUA_HOME` 可覆盖） |
| `install\clink-fzf.ps1` | `C:\Software\clink\fzf` |
| `install\clink-gizmos.ps1` | `C:\Software\clink\gizmos` |

在 `%CLINK_PROFILE%\install\` 下执行对应脚本，会在 profile 目录创建符号链接。

## 自动添加部分

### pnpm 路径

```cmd
PNPM_HOME=C:\Users\witty\AppData\Local\pnpm （pnpm setup）
```

### Clink 安装目录

```cmd
CLINK_DIR=C:\Program Files (x86)\clink （clink安装程序）
```
