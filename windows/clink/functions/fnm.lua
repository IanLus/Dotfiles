-- Initialize fnm for Clink/CMD, with auto version switch on directory change.
--
-- Matches WSL zsh recursive use-on-cd: always `fnm use --silent-if-unchanged`
-- on cwd change (no version-file existence guard). That is what reverts Node
-- to the default alias when leaving a project tree.
--
-- Official `fnm env --use-on-cd` only wraps `cd` via doskey. That misses z.lua
-- (and pushd etc.), because z.cmd runs `cd /d` inside a batch file where doskey
-- aliases are not expanded. So we also hook clink.onbeginedit.
--
-- Important: do NOT os.execute interactive `fnm use` from onbeginedit — Clink
-- already owns the console for line editing, so fnm's y/N prompt appears to hang.
-- Capture output non-interactively, then ask with Lua io.read if needed.

if os.getenv("FNM_AUTORUN_GUARD") then
	return
end

-- Prefer recursive (WSL intent). Respect an existing FNM_VERSION_FILE_STRATEGY.
local env_cmd = "fnm env --use-on-cd --shell cmd"
if not os.getenv("FNM_VERSION_FILE_STRATEGY") then
	env_cmd = env_cmd .. " --version-file-strategy=recursive"
end

local pipe = io.popen(env_cmd .. " 2>nul")
if not pipe then
	return
end

local out = pipe:read("*a") or ""
pipe:close()
if out == "" then
	return
end

os.setenv("FNM_AUTORUN_GUARD", "AutorunGuard")

for line in out:gmatch("[^\r\n]+") do
	local name, value = line:match("^SET ([^=]+)=(.*)$")
	if name then
		os.setenv(name, value)
	else
		-- Keep doskey cd=... for immediate switch on typed `cd` (and `cd && ...`).
		local alias_name, alias_def = line:match("^doskey ([^=]+)=(.*)$")
		if alias_name and alias_def and os.setalias then
			os.setalias(alias_name, alias_def)
		end
	end
end

local function script_dir()
	local src = debug.getinfo(1, "S").source
	if src:sub(1, 1) == "@" then
		src = src:sub(2)
	end
	return src:match("^(.*)[/\\]") or "."
end

local function remove_multishell_link()
	local path = os.getenv("FNM_MULTISHELL_PATH")
	if not path or path == "" or not path:find("fnm_multishells", 1, true) then
		return
	end
	os.execute('rmdir "' .. path .. '" >nul 2>nul')
end

-- fnm never deletes the per-session symlink. CMD has no EXIT trap; a waiter
-- covers `exit`, Ctrl+D, and closing the Windows Terminal tab.
local function start_multishell_cleanup_waiter()
	local path = os.getenv("FNM_MULTISHELL_PATH")
	local pid = os.getpid and os.getpid()
	if not path or path == "" or not pid then
		return
	end
	if not path:find("fnm_multishells", 1, true) then
		return
	end
	local exe = script_dir() .. "\\..\\tools\\fnm_multishell_cleanup.exe"
	if os.isfile and not os.isfile(exe) then
		return
	end
	os.execute(string.format('start "" /b "%s" %d "%s"', exe, pid, path))
end

start_multishell_cleanup_waiter()

if clink.onfilterinput then
	clink.onfilterinput(function(line)
		local cmd = line:match("^%s*(%S+)")
		if cmd and cmd:lower() == "exit" then
			remove_multishell_link()
		end
	end)
end

local function cwd()
	if os.getcwd then
		return os.getcwd()
	end
	if clink.get_cwd then
		return clink.get_cwd()
	end
	return nil
end

-- Official Windows cd.cmd (local strategy): only .nvmrc / .node-version.
local function has_local_version_file()
	local nvmrc = io.open(".nvmrc", "r")
	if nvmrc then
		nvmrc:close()
		return true
	end
	local node_version = io.open(".node-version", "r")
	if node_version then
		node_version:close()
		return true
	end
	return false
end

local function strip_ansi(s)
	return (s:gsub("\27%[[%d;]*m", ""))
end

local function handle_fnm_output(text)
	if text == "" then
		return
	end

	-- Interactive TTY: "Can't find an installed Node version matching vX..."
	-- Non-interactive (<nul / pipe): "error: Requested version vX is not currently installed"
	local missing = text:match("[Cc]an't find an installed Node version matching%s+(%S+)")
		or text:match("[Rr]equested version%s+(%S+)%s+is not currently installed")
	if missing then
		missing = missing:gsub("%.$", "")
		io.write("Can't find an installed Node version matching " .. missing .. ".\n")
		io.write("Do you want to install it? [y/N]: ")
		io.flush()
		local answer = io.read("*l")
		if answer and answer:lower():match("^y") then
			os.execute("fnm use --silent-if-unchanged --install-if-missing")
		end
		return
	end

	local used = text:match("Using Node%s+(v[%d%.]+)")
		or text:match("Using Node for alias (%S+)")
	if used then
		print("Using Node " .. used)
	end
end

---Run a fnm use variant without letting it steal stdin from Clink.
local function fnm_popen(args)
	local handle = io.popen("fnm " .. args .. " <nul 2>&1")
	if not handle then
		return
	end
	local text = strip_ansi(handle:read("*a") or "")
	handle:close()
	handle_fnm_output(text)
end

local last_cwd

local function onbeginedit()
	local now = cwd()
	if not now or now == last_cwd then
		return
	end
	last_cwd = now

	-- recursive (WSL / official cd.cmd): always fnm use — falls back to default
	-- when no version file is found up the tree.
	if os.getenv("FNM_VERSION_FILE_STRATEGY") == "recursive" then
		fnm_popen("use --silent-if-unchanged")
		return
	end

	-- local fallback: official cd.cmd only uses when a file exists; we still
	-- revert to default on leave so Node does not stick after leaving a project.
	if has_local_version_file() then
		fnm_popen("use --silent-if-unchanged")
	else
		fnm_popen("use default --silent-if-unchanged")
	end
end

if clink.onbeginedit then
	clink.onbeginedit(onbeginedit)
else
	print("fnm.lua: clink.onbeginedit missing; z/pushd will not auto-switch Node.")
end
