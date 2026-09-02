-- Filesystem commands for Clink (cmd.exe).
-- mkcd <dir>   : create directory if missing, then cd into it
-- rm [opts]    : bash-like remove files / directories (-r -f -d -v)
-- which lives in functions/which.lua (shared with fzf preview).

local glob_flags = { hidden = true, system = true }

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
	s = tostring(s):gsub('"', "")
	-- Trailing `\` would eat the closing quote (`rmdir "C:\dir\"`).
	if s:sub(-1) == "\\" then
		s = s .. "\\"
	end
	return '"' .. s .. '"'
end

-- `cmd /c` is not a batch file: `%%VAR%%` still expands `%VAR%`.
local function quote_cmd_exec(s)
	return quote_cmd(tostring(s):gsub("%%", "^%%"))
end

local function env_var_value(name)
	if not name or name == "" then
		return nil
	end
	if name:lower() == "cd" then
		return os.getcwd and os.getcwd() or nil
	end
	local v = os.getenv(name)
	if v and v ~= "" then
		return v
	end
	return nil
end

local function expand_env(path)
	if os.expand_env then
		path = os.expand_env(path) or path
	end
	return (path:gsub("%%([^%%]+)%%", function(name)
		return env_var_value(name) or ("%" .. name .. "%")
	end))
end

local function home_dir()
	if rl.expandtilde then
		local home = rl.expandtilde("~")
		if home and home ~= "" and home ~= "~" then
			return home:gsub("[/\\]+$", "")
		end
	end
	local home = os.getenv("HOME") or os.getenv("USERPROFILE")
	if home and home ~= "" then
		return home:gsub("[/\\]+$", "")
	end
	return nil
end

local function norm_path(p)
	return (p or ""):gsub("/", "\\"):gsub("\\+$", ""):lower()
end

local function is_abs_win(p)
	return p:match("^%a:[/\\]") ~= nil or p:match("^%a:$") ~= nil or p:sub(1, 2) == "\\\\"
end

local function is_rel_prefixed(p)
	return p:match("^~") ~= nil or p:match("^%.%.?[\\/]") ~= nil
end

local function env_name_for_value(abs)
	local n = norm_path(abs)
	if n == "" then
		return nil
	end
	local function check(name)
		local v = env_var_value(name)
		if v and norm_path(v) == n then
			return name
		end
		return nil
	end
	if check("DOTDIR") then
		return "DOTDIR"
	end
	if os.enum_env_vars then
		for _, name in ipairs(os.enum_env_vars() or {}) do
			if check(name) then
				return name
			end
		end
	end
	return nil
end

-- `.\%DOTDIR%` / `~\%DOTDIR%` is the folder literally named `%DOTDIR%`
-- under cwd/home. Only expand `%VAR%` when it starts the path.
local function expand_path(path)
	path = (path or ""):gsub('^"(.-)"$', "%1"):gsub("/", "\\")

	-- Already-expanded `.\%DOTDIR%` → `.\C:\...\dotfiles`: map back to `%NAME%`.
	local rel, rest = path:match("^(%.%.)[\\](.*)$")
	if not rel then
		rel, rest = path:match("^(%.)[\\](.*)$")
	end
	if not rel then
		rel, rest = path:match("^(~)[\\](.*)$")
	end
	if rel and rest and is_abs_win(rest) then
		local name = env_name_for_value(rest)
		if name then
			path = rel .. "\\" .. "%" .. name .. "%"
		end
	end

	if path:match("^%%[^%%]+%%") then
		path = expand_env(path)
	end

	rest = path:match("^~[\\](.*)$") or (path == "~" and "")
	if rest then
		local home = home_dir()
		if home then
			path = rest == "" and home or (home .. "\\" .. rest:gsub("^\\+", ""))
		end
	end

	if path:match("^%a:$") then
		return path .. "\\"
	end
	if not path:match("^%a:\\$") then
		path = path:gsub("\\+$", "")
	end

	-- Keep `%` names literal. Join `.\` / `..\` onto cwd ourselves.
	if path:find("%%", 1, true) then
		local cwd = os.getcwd and os.getcwd() or ""
		if path:match("^%.%.[\\]") then
			local parent = cwd:match("^(.*)[\\/][^\\/]+$") or cwd
			return parent .. "\\" .. path:gsub("^%.%.[\\]+", "")
		end
		if path:match("^%.[\\]") then
			return cwd .. "\\" .. path:gsub("^%.[\\]+", "")
		end
		return path
	end

	if os.getfullpathname and path ~= "" then
		path = os.getfullpathname(path) or path
	end
	return path
end

local function resolves_to_env_original(raw, resolved)
	if not is_rel_prefixed(raw) then
		return false
	end
	local resolved_n = norm_path(resolved)
	if resolved_n == "" then
		return false
	end
	for name in raw:gmatch("%%([^%%]+)%%") do
		local v = env_var_value(name)
		if v and norm_path(v) == resolved_n then
			return true
		end
	end
	local rest = raw:match("^%.%.?[\\/](.*)$") or raw:match("^~[\\/](.*)$")
	if not rest then
		return false
	end
	rest = rest:gsub("\\+$", "")
	return is_abs_win(rest) and norm_path(rest) == resolved_n
end

--------------------------------------------------------------------------------
-- mkcd

local function mkcd(rest)
	local dir = first_arg(rest)
	if not dir then
		print("用法: mkcd <dir>")
		return "", false
	end
	return "mkdir " .. quote_cmd(dir) .. " 2>nul & cd /d " .. quote_cmd(dir), false
end

--------------------------------------------------------------------------------
-- rm (bash-like)

local function split_args(rest)
	local args = {}
	rest = rest or ""
	while true do
		rest = rest:match("^%s*(.*)$") or ""
		if rest == "" then
			break
		end
		if rest:sub(1, 1) == '"' then
			local quoted, after = rest:match('^"(.-)"(.*)$')
			if not quoted then
				table.insert(args, rest:sub(2))
				break
			end
			table.insert(args, quoted)
			rest = after
		else
			local tok, after = rest:match("^(%S+)(.*)$")
			table.insert(args, tok)
			rest = after
		end
	end
	return args
end

local function rm_usage()
	print("用法: rm [-rfvd] [--] <path>...")
	print("  -r, -R, --recursive  递归删除目录")
	print("  -f, --force          忽略不存在的路径；强制删除只读文件")
	print("  -d, --dir            删除空目录")
	print("  -v, --verbose        显示删除的路径")
end

local function is_dot_or_dotdot(name)
	return name == "." or name == ".."
end

local function rm_dangerous(path)
	local n = path:gsub("/", "\\"):gsub("\\+$", "")
	if n == "" or is_dot_or_dotdot(n) then
		return true
	end
	if n:match("^[A-Za-z]:$") or n:match("^[A-Za-z]:\\$") then
		return true
	end
	return false
end

local function path_exists(path)
	if os.isdir and os.isdir(path) then
		return true, "dir"
	end
	if os.isfile and os.isfile(path) then
		return true, "file"
	end
	local f = io.open(path, "rb")
	if f then
		f:close()
		return true, "file"
	end
	return false, nil
end

local function rm_exec(cmd)
	if os.execute then
		os.execute(cmd)
	end
end

local function entry_name(entry)
	return type(entry) == "table" and entry.name or entry
end

local function entry_type(entry)
	return type(entry) == "table" and (entry.type or "") or ""
end

local function child_full(dir, entry)
	local name = entry_name(entry)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local base = name:match("[^\\/]+$") or name
	if is_dot_or_dotdot(base) then
		return nil
	end
	if name:match("^%a:") or name:match("^[\\/]") then
		return name
	end
	return dir .. "\\" .. base
end

local function glob_try(fn, pattern)
	if not fn then
		return {}
	end
	local ok, result = pcall(fn, pattern, true, glob_flags)
	if not (ok and type(result) == "table") then
		ok, result = pcall(fn, pattern, true)
	end
	if ok and type(result) == "table" then
		return result
	end
	return {}
end

local function glob_children(path)
	local pattern = path .. "\\*"
	local out = {}
	for _, e in ipairs(glob_try(os.globfiles, pattern)) do
		out[#out + 1] = e
	end
	for _, e in ipairs(glob_try(os.globdirs, pattern)) do
		out[#out + 1] = e
	end
	return out
end

-- NTFS reparse points: unlink the entry only, never walk the target.
local function is_reparse_point(path)
	if os.issymlink and os.issymlink(path) then
		return true
	end
	local parent, base = path:match("^(.*)[\\/]([^\\/]+)$")
	if parent and base then
		for _, e in ipairs(glob_children(parent)) do
			local name = entry_name(e)
			local leaf = name and (name:match("[^\\/]+$") or name)
			if leaf and leaf:lower() == base:lower() then
				return entry_type(e):find("link", 1, true) ~= nil
			end
		end
	end
	if path:find("%%", 1, true) then
		return false
	end
	local p = io.popen("fsutil reparsepoint query " .. quote_cmd_exec(path) .. " 2>nul")
	if not p then
		return false
	end
	local out = p:read("*a") or ""
	p:close()
	return out:find("Reparse Tag", 1, true) ~= nil
end

local function rm_file(path)
	if os.unlink and os.unlink(path) then
		return true
	end
	if os.remove and os.remove(path) then
		return true
	end
	rm_exec("del /f /q " .. quote_cmd_exec(path))
	return true
end

local function rm_empty_dir(path)
	if os.rmdir then
		return os.rmdir(path)
	end
	rm_exec("rmdir " .. quote_cmd_exec(path))
	return true
end

local function rm_reparse_entry(path)
	if os.isdir and os.isdir(path) then
		return rm_empty_dir(path)
	end
	return rm_file(path)
end

-- Win32 APIs treat `%` as a literal name. Do not `rmdir /s` through CMD.
local function rm_tree(path)
	if is_reparse_point(path) then
		return rm_reparse_entry(path)
	end
	local seen = {}
	for _, e in ipairs(glob_children(path)) do
		local full = child_full(path, e)
		if full then
			local key = full:lower()
			if not seen[key] then
				seen[key] = true
				local typ = entry_type(e)
				if typ:find("link", 1, true) then
					rm_reparse_entry(full)
				elseif typ:find("dir", 1, true) or (os.isdir and os.isdir(full)) then
					rm_tree(full)
				else
					rm_file(full)
				end
			end
		end
	end
	return rm_empty_dir(path)
end

local function glob_expand(path)
	if not path:find("[*?]") then
		return { path }
	end
	local matches = {}
	local seen = {}
	local prefix = path:match("^(.*)[\\/][^\\/]*$")
	local function add(entry)
		local name = entry_name(entry)
		if type(name) ~= "string" or name == "" then
			return
		end
		name = name:gsub("[\\/]+$", "")
		local base = name:match("[^\\/]+$") or name
		if is_dot_or_dotdot(base) then
			return
		end
		if prefix and prefix ~= "" and not name:match("^[A-Za-z]:") and not name:match("^[\\/]") then
			name = prefix .. "\\" .. name
		end
		if os.getfullpathname and not name:find("%%", 1, true) then
			name = os.getfullpathname(name) or name
		end
		if not seen[name] then
			seen[name] = true
			table.insert(matches, name)
		end
	end
	for _, m in ipairs(glob_try(os.globfiles, path)) do
		add(m)
	end
	if os.globdirs then
		for _, m in ipairs(glob_try(os.globdirs, path)) do
			add(m)
		end
	elseif os.glob then
		for _, m in ipairs(os.glob(path) or {}) do
			add(m)
		end
	end
	return matches
end

local function rm_one(path, recursive, empty_dir, force, verbose)
	if rm_dangerous(path) then
		print("rm: 拒绝删除 '" .. path .. "'")
		return
	end
	local exists, kind = path_exists(path)
	if not exists then
		if not force then
			print("rm: 无法删除 '" .. path .. "': 没有那个文件或目录")
		end
		return
	end
	if is_reparse_point(path) then
		if verbose then
			print("removed link '" .. path .. "'")
		end
		rm_reparse_entry(path)
		return
	end
	if kind == "dir" then
		if recursive then
			if verbose then
				print("removed directory '" .. path .. "'")
			end
			rm_tree(path)
		elseif empty_dir then
			if verbose then
				print("removed directory '" .. path .. "'")
			end
			rm_empty_dir(path)
		else
			print("rm: 无法删除 '" .. path .. "': 是一个目录")
		end
		return
	end
	if verbose then
		print("removed '" .. path .. "'")
	end
	rm_file(path)
end

local function rm_cmd(rest)
	local args = split_args(rest)
	local recursive = false
	local force = false
	local empty_dir = false
	local verbose = false
	local paths = {}
	local only_paths = false

	for _, a in ipairs(args) do
		if only_paths then
			table.insert(paths, a)
		elseif a == "--" then
			only_paths = true
		elseif a == "--help" or a == "-h" then
			rm_usage()
			return "", false
		elseif a == "--recursive" then
			recursive = true
		elseif a == "--force" then
			force = true
		elseif a == "--dir" then
			empty_dir = true
		elseif a == "--verbose" then
			verbose = true
		elseif a:sub(1, 1) == "-" and #a > 1 and a:sub(2, 2) ~= "-" then
			for c in a:sub(2):gmatch(".") do
				if c == "r" or c == "R" then
					recursive = true
				elseif c == "f" then
					force = true
				elseif c == "d" then
					empty_dir = true
				elseif c == "v" then
					verbose = true
				elseif c == "h" then
					rm_usage()
					return "", false
				else
					print("rm: 未知选项 -- " .. c)
					rm_usage()
					return "", false
				end
			end
		else
			table.insert(paths, a)
		end
	end

	if #paths == 0 then
		rm_usage()
		return "", false
	end

	for _, raw in ipairs(paths) do
		local target = expand_path(raw)
		if resolves_to_env_original(raw, target) then
			print("rm: 拒绝删除 '" .. raw .. "': 相对路径会指向环境变量的原目录")
		else
			local expanded = glob_expand(target)
			if #expanded == 0 and not force then
				print("rm: 无法删除 '" .. raw .. "': 没有那个文件或目录")
			end
			for _, path in ipairs(expanded) do
				rm_one(path, recursive, empty_dir, force, verbose)
			end
		end
	end

	return "", false
end

--------------------------------------------------------------------------------

local commands = {
	mkcd = mkcd,
	rm = rm_cmd,
}

local function onfilterinput(line)
	local cmd, rest = line:match("^%s*(%S+)(.*)$")
	if not cmd then
		return
	end
	local handler = commands[cmd:lower()]
	if not handler then
		return
	end
	return handler(rest)
end

if clink.onfilterinput then
	clink.onfilterinput(onfilterinput)
	if register_clink_lua_command then
		register_clink_lua_command("mkcd")
		register_clink_lua_command("rm")
	end
else
	print("fs.lua requires a newer version of Clink; please upgrade.")
end
