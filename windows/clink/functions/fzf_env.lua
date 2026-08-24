-- clink-fzf preview and FZF_* options (cmd/clink only; not Windows user env).
-- Clink settings (fzf.height, fzf_rg.show_preview, ...) are written by install/fzf.ps1.

local function set_default(name, value)
	if os.getenv(name) == nil or os.getenv(name) == "" then
		os.setenv(name, value)
	end
end

local function command_on_path(name)
	local r = io.popen("where " .. name .. " 2>nul")
	if not r then
		return false
	end
	local line = r:read("*l")
	r:close()
	return line ~= nil and line ~= ""
end

-- Relative paths for Ctrl+T and ** Tab (dirx on PATH; install/dirx.ps1 -> C:\Software\dirx).
if command_on_path("dirx.exe") then
	set_default("FZF_CTRL_T_COMMAND", "fzf-list-files.cmd $dir")
	set_default("FZF_ALT_C_COMMAND", "fzf-list-dirs.cmd $dir")
end

-- Alt+C stays reverse-only; do not copy common_env's tree preview.
local fzf_file_opts = table.concat({
	"--layout=reverse",
	'--preview "fzf-preview.cmd {}"',
	"--preview-window 65%",
	'--bind "ctrl-/:change-preview-window(down|hidden|),ctrl-f:preview-page-down,ctrl-b:preview-page-up"',
}, " ")

set_default("CLINK_FZF_PREVIEW_SIXELS", "1")

set_default("FZF_DEFAULT_OPTS", "--border=rounded --info=inline --scrollbar=▌")

os.setenv("FZF_CTRL_T_OPTS", fzf_file_opts)
set_default("FZF_COMPLETION_OPTS", fzf_file_opts)
os.setenv("FZF_ALT_C_OPTS", "--layout=reverse")

-- Ctrl+R：输入框在 fzf 窗口顶部
os.setenv("FZF_CTRL_R_OPTS", "--layout=reverse")

set_default("FZF_GIT_CAT", "bat --style=numbers,changes --color=always --pager=never")
