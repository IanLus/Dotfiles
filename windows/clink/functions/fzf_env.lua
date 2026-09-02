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
-- Alt+H / Alt+I match zsh fd-toggle.sh. Header must not contain `|` (cmd pipe).
-- alt-h / alt-i each need their own --bind; a comma after transform: is consumed.
local has_dirx = command_on_path("dirx.exe")
if has_dirx then
	-- Profile-local path (not an official fzf variable). Holds hidden/ignore/root
	-- for Alt+H / Alt+I. Recreated on each Ctrl+T if TEMP files were wiped.
	local tmp = os.getenv("TEMP") or os.getenv("TMP") or ""
	if tmp == "" then
		local localapp = os.getenv("LOCALAPPDATA")
		tmp = (localapp and localapp ~= "") and (localapp .. "\\Temp") or "."
	end
	if os.isdir and not os.isdir(tmp) and os.mkdir then
		os.mkdir(tmp)
	end
	local id = (os.getpid and os.getpid()) or os.getenv("USERNAME") or "user"
	os.setenv("FZF_FD_STATE", tmp .. "\\fzf-fd-" .. tostring(id) .. ".txt")
	local ctrl_t = os.getenv("FZF_CTRL_T_COMMAND")
	if not ctrl_t or ctrl_t == "" or ctrl_t:find("fzf%-fd%-toggle%.cmd") then
		os.setenv("FZF_CTRL_T_COMMAND", "fzf-list-files.cmd $dir")
	end
	set_default("FZF_ALT_C_COMMAND", "fzf-list-dirs.cmd $dir")
end

-- Alt+C stays reverse-only; do not copy common_env's tree preview.
local fzf_file_opts = table.concat({
	"--layout=reverse",
	'--preview "fzf-preview.cmd {}"',
	"--preview-window 65%",
	'--bind "ctrl-/:change-preview-window(down|hidden|),ctrl-f:preview-page-down,ctrl-b:preview-page-up"',
}, " ")

-- Only Ctrl+T / ** (not ordinary Tab over already-built matches).
local fzf_fd_toggle_opts = table.concat({
	'--header "alt-h: hidden off / alt-i: ignore off"',
	'--bind "alt-h:transform:fzf-fd-toggle.cmd hidden"',
	'--bind "alt-i:transform:fzf-fd-toggle.cmd ignore"',
}, " ")

set_default("CLINK_FZF_PREVIEW_SIXELS", "1")

set_default("FZF_DEFAULT_OPTS", "--border=rounded --info=inline --scrollbar=▌")

if has_dirx then
	os.setenv("FZF_CTRL_T_OPTS", fzf_file_opts .. " " .. fzf_fd_toggle_opts)
	os.setenv("FZF_FD_TOGGLE_OPTS", fzf_fd_toggle_opts)
else
	os.setenv("FZF_CTRL_T_OPTS", fzf_file_opts)
end
set_default("FZF_COMPLETION_OPTS", fzf_file_opts)
os.setenv("FZF_ALT_C_OPTS", "--layout=reverse")

-- Ctrl+R：输入框在 fzf 窗口顶部
os.setenv("FZF_CTRL_R_OPTS", "--layout=reverse")

set_default("FZF_GIT_CAT", "bat --style=numbers,changes --color=always --pager=never")
