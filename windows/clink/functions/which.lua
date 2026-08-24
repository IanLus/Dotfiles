-- Shared `which` for Clink and fzf preview.
-- Clink: onfilterinput command (os.getalias / clink_lua_commands).
-- Preview: lua.exe functions/which.lua <name> (reads aliases.lua + register_clink_lua_command).
-- Resolution order is the same in both backends.

local M = {}

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function first_arg(rest)
	rest = trim(rest or "")
	if rest == "" then
		return nil
	end
	local quoted = rest:match('^"(.-)"')
	if quoted then
		return quoted
	end
	return rest:match("^(%S+)")
end

local function quote_cmd(s)
	return '"' .. tostring(s):gsub('"', "") .. '"'
end

local function read_all(path)
	local f = io.open(path, "r")
	if not f then
		return ""
	end
	local text = f:read("*a") or ""
	f:close()
	return text
end

local cmd_builtins = {
	assoc = true,
	["break"] = true,
	call = true,
	cd = true,
	chdir = true,
	cls = true,
	color = true,
	copy = true,
	date = true,
	del = true,
	dir = true,
	dpath = true,
	echo = true,
	endlocal = true,
	erase = true,
	exit = true,
	["for"] = true,
	ftype = true,
	["goto"] = true,
	["if"] = true,
	keys = true,
	md = true,
	mkdir = true,
	mklink = true,
	move = true,
	path = true,
	pause = true,
	popd = true,
	prompt = true,
	pushd = true,
	rd = true,
	rem = true,
	ren = true,
	rename = true,
	rmdir = true,
	set = true,
	setlocal = true,
	shift = true,
	start = true,
	time = true,
	title = true,
	type = true,
	ver = true,
	verify = true,
	vol = true,
}

local function is_cmd_builtin(name)
	return cmd_builtins[name:lower()] == true
end

local function where_paths(name)
	local paths = {}
	local f = io.popen("where.exe " .. quote_cmd(name) .. " 2>nul")
	if not f then
		return paths
	end
	for line in f:lines() do
		if line ~= "" then
			table.insert(paths, line)
		end
	end
	f:close()
	return paths
end

local function first_token(expansion)
	expansion = (expansion or ""):gsub("^%s+", "")
	return expansion:match('^"([^"]+)"') or expansion:match("^(%S+)") or expansion
end

local function is_not_found(lines)
	return #lines == 1 and lines[1]:find(": not found$") ~= nil
end

function M.clink_backend()
	return {
		is_lua_command = function(name)
			local key = name:lower()
			return clink_lua_commands and clink_lua_commands[key] ~= nil
		end,
		get_alias = function(name)
			if not os.getalias then
				return nil
			end
			local alias = os.getalias(name)
			if not alias or alias == "" then
				return nil
			end
			return alias
		end,
	}
end

function M.profile_dir()
	local env = os.getenv("CLINK_PROFILE")
	if env and env ~= "" then
		return env:gsub("[/\\]+$", "")
	end
	local src = debug.getinfo(1, "S").source
	if src:sub(1, 1) == "@" then
		src = src:sub(2)
	end
	return src:match("^(.*)[/\\]functions[/\\]") or src:match("^(.*)[/\\]") or "."
end

function M.file_backend(profile)
	profile = profile or M.profile_dir()
	local lua_cmds, aliases

	local function load_maps()
		if lua_cmds then
			return
		end
		lua_cmds = {}
		aliases = {}

		-- Only open files that actually register a Lua command (skip fzf_env, etc.).
		local listing = io.popen(
			'findstr /i /m /c:"register_clink_lua_command" "'
				.. profile
				.. '\\functions\\*.lua" 2>nul'
		)
		if listing then
			for path in listing:lines() do
				for cmd in read_all(path):gmatch('register_clink_lua_command%s*%(%s*"([^"]+)"') do
					lua_cmds[cmd:lower()] = true
				end
			end
			listing:close()
		end

		for name, exp in read_all(profile .. "\\aliases\\init.lua"):gmatch(
			'os%.setalias%s*%(%s*"([^"]+)"%s*,%s*"([^"]*)"'
		) do
			aliases[name:lower()] = exp
		end
	end

	return {
		is_lua_command = function(name)
			load_maps()
			return lua_cmds[name:lower()] == true
		end,
		get_alias = function(name)
			load_maps()
			return aliases[name:lower()]
		end,
	}
end

function M.backend()
	if rawget(_G, "clink") then
		return M.clink_backend()
	end
	return M.file_backend()
end

function M.resolve(name, backend, seen)
	backend = backend or M.backend()
	seen = seen or {}
	local key = name:lower()
	if seen[key] then
		return name
	end
	seen[key] = true

	if backend.is_lua_command(name) then
		return name .. " (Clink Lua command)"
	end

	local alias = backend.get_alias(name)
	if alias and alias ~= "" then
		return M.resolve(first_token(alias), backend, seen)
	end

	if is_cmd_builtin(name) then
		return name .. " (CMD internal command)"
	end

	local paths = where_paths(name)
	if paths[1] then
		return paths[1]
	end
	return name
end

function M.lines(name, backend)
	backend = backend or M.backend()

	if backend.is_lua_command(name) then
		return { name .. ": Clink Lua command" }
	end

	local alias = backend.get_alias(name)
	if alias and alias ~= "" then
		return { string.format("%s: Alias for (%s)", name, M.resolve(name, backend)) }
	end

	if is_cmd_builtin(name) then
		return { name .. ": CMD internal command" }
	end

	local paths = where_paths(name)
	if #paths > 0 then
		return paths
	end

	return { name .. ": not found" }
end

-- PE / libraries: preview with `which` (path), not file contents.
local binary_ext = {
	exe = true,
	com = true,
	dll = true,
	sys = true,
	scr = true,
	pyd = true,
	cpl = true,
	ocx = true,
	drv = true,
	efi = true,
}

local function path_ext(path)
	local ext = path:lower():match("%.([^.\\/]+)$")
	return ext or ""
end

function M.is_binary_path(path)
	return binary_ext[path_ext(path)] == true
end

-- fzf-preview.cmd --preview: readable PATH scripts return the file to bat/eza;
-- aliases, Lua commands, builtins, and binaries stay as which text.
-- Returns kind "file" + path, "which" + lines, or "missing".
function M.preview_target(name, backend)
	backend = backend or M.backend()
	if backend.is_lua_command(name) then
		return "which", { name .. ": Clink Lua command" }
	end
	local alias = backend.get_alias(name)
	if alias and alias ~= "" then
		return "which", { string.format("%s: Alias for (%s)", name, M.resolve(name, backend)) }
	end
	if is_cmd_builtin(name) then
		return "which", { name .. ": CMD internal command" }
	end
	local paths = where_paths(name)
	if not paths[1] then
		return "missing", nil
	end
	if M.is_binary_path(paths[1]) then
		return "which", paths
	end
	return "file", paths[1]
end

if not rawget(_G, "clink") then
	if arg and arg[1] == "--preview" then
		local name = arg[2]
		if not name or name == "" then
			os.exit(2)
		end
		local kind, payload = M.preview_target(name, M.file_backend())
		if kind == "file" then
			io.stdout:write(payload .. "\n")
			os.exit(0)
		end
		if kind == "which" then
			for i = 1, #payload do
				print(payload[i])
			end
			os.exit(1)
		end
		os.exit(2)
	end
	local name = arg and arg[1]
	if name and name ~= "" then
		local lines = M.lines(name, M.file_backend())
		if is_not_found(lines) then
			os.exit(1)
		end
		for i = 1, #lines do
			print(lines[i])
		end
		os.exit(0)
	end
elseif clink.onfilterinput then
	local function which_cmd(rest)
		local name = first_arg(rest)
		if not name then
			print("用法: which <name>")
			return "", false
		end
		for _, line in ipairs(M.lines(name, M.clink_backend())) do
			print(line)
		end
		return "", false
	end

	clink.onfilterinput(function(line)
		local cmd, rest = line:match("^%s*(%S+)(.*)$")
		if not cmd or cmd:lower() ~= "which" then
			return
		end
		return which_cmd(rest)
	end)
	if register_clink_lua_command then
		register_clink_lua_command("which")
	end
else
	print("which.lua requires a newer version of Clink; please upgrade.")
end

return M
