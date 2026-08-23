-- Toggle %GIT%\usr\bin on PATH (enable-linux-tools / disable-linux-tools).
-- enable-linux-tools  (alias: elt)
-- disable-linux-tools (alias: dlt)

local function git_usr_bin()
	local git = os.getenv("GIT")
	if not git or git == "" then
		return nil
	end
	git = git:gsub("[/\\]+$", "")
	return git .. "\\usr\\bin"
end

local function split_path(path)
	local parts = {}
	for part in string.gmatch(path or "", "[^;]+") do
		if part ~= "" then
			table.insert(parts, part)
		end
	end
	return parts
end

local function path_index_of(parts, target)
	local target_lower = target:lower()
	for i, part in ipairs(parts) do
		if part:lower() == target_lower then
			return i
		end
	end
	return -1
end

local function enable_linux_tools()
	local usr_bin = git_usr_bin()
	if not usr_bin then
		print("GIT environment variable is not set.")
		return
	end
	local parts = split_path(os.getenv("PATH"))
	if path_index_of(parts, usr_bin) == -1 then
		table.insert(parts, usr_bin)
		os.setenv("PATH", table.concat(parts, ";"))
	end
end

local function disable_linux_tools()
	local usr_bin = git_usr_bin()
	if not usr_bin then
		return
	end
	local parts = split_path(os.getenv("PATH"))
	local filtered = {}
	local target_lower = usr_bin:lower()
	for _, part in ipairs(parts) do
		if part:lower() ~= target_lower then
			table.insert(filtered, part)
		end
	end
	os.setenv("PATH", table.concat(filtered, ";"))
end

local commands = {
	["enable-linux-tools"] = enable_linux_tools,
	["disable-linux-tools"] = disable_linux_tools,
}

local function alias_target(name)
	local alias = os.getalias and os.getalias(name)
	if not alias or alias == "" then
		return nil
	end
	return alias:match('^"([^"]+)"') or alias:match("^(%S+)")
end

local function onfilterinput(line)
	local cmd = line:match("^%s*(%S+)")
	if not cmd then
		return
	end
	local handler = commands[cmd:lower()]
	if not handler then
		local target = alias_target(cmd)
		if target then
			handler = commands[target:lower()]
		end
	end
	if not handler then
		return
	end
	handler()
	return "", false
end

if clink.onfilterinput then
	clink.onfilterinput(onfilterinput)
	if register_clink_lua_command then
		register_clink_lua_command("enable-linux-tools")
		register_clink_lua_command("disable-linux-tools")
	end
else
	print("unix_tools.lua requires a newer version of Clink; please upgrade.")
end
