-- Filesystem commands for Clink (cmd.exe).
-- mkcd <dir>   : create directory if missing, then cd into it
-- rm [opts]    : bash-like remove files / directories (-r -f -d -v)
-- which lives in functions/which.lua (shared with fzf preview).

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
	-- Drive root: C: or C:\
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
	-- Fallback when stubs/APIs differ (reparse points, etc.)
	local f = io.open(path, "rb")
	if f then
		f:close()
		return true, "file"
	end
	return false, nil
end

local function glob_expand(path)
	if not path:find("[*?]") then
		return { path }
	end
	local matches = {}
	if os.glob then
		local g = os.glob(path)
		if type(g) == "table" then
			for _, m in ipairs(g) do
				if type(m) == "string" and m ~= "" then
					table.insert(matches, m)
				elseif type(m) == "table" and m.name then
					table.insert(matches, m.name)
				end
			end
		end
	end
	return matches
end

local function rm_exec(cmd)
	if os.execute then
		os.execute(cmd)
	end
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
		local expanded = glob_expand(raw)
		if #expanded == 0 then
			if not force then
				print("rm: 无法删除 '" .. raw .. "': 没有那个文件或目录")
			end
		end
		for _, path in ipairs(expanded) do
			if rm_dangerous(path) then
				print("rm: 拒绝删除 '" .. path .. "'")
			else
				local exists, kind = path_exists(path)
				if not exists then
					if not force then
						print("rm: 无法删除 '" .. path .. "': 没有那个文件或目录")
					end
				elseif kind == "dir" then
					if recursive then
						if verbose then
							print("removed directory '" .. path .. "'")
						end
						rm_exec("rmdir /s /q " .. quote_cmd(path))
					elseif empty_dir then
						if verbose then
							print("removed directory '" .. path .. "'")
						end
						rm_exec("rmdir " .. quote_cmd(path))
					else
						print("rm: 无法删除 '" .. path .. "': 是一个目录")
					end
				else
					if verbose then
						print("removed '" .. path .. "'")
					end
					if force then
						rm_exec("del /f /q " .. quote_cmd(path))
					else
						rm_exec("del /q " .. quote_cmd(path))
					end
				end
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
