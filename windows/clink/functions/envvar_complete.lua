-- CMD %VAR% completion:
--   %dot<Tab>     → %DOTDIR%\          (name; directory values get \)
--   %DOTDIR%<Tab> → C:\...\dotfiles    (expand the value; match.expand_envvars)
--   %DOTDIR%\<Tab> stays %DOTDIR%\ and completes files relative to that dir
--   Space after %DOTDIR%\ → %DOTDIR%
-- Non-directory values (e.g. %ALL_PROXY%) stay unsuffixed.
--
-- %VAR%\ must not go through match.expand_envvars: that rewrites the line to
-- the absolute path. Truncate past %VAR% so expand only sees the relative part.
-- Path matches are the last component only (prefix stays on the line).

local special_env_vars = {
	"cd",
	"date",
	"time",
	"random",
	"errorlevel",
	"cmdextversion",
	"cmdcmdline",
	"highestnumanodenumber",
}

local dir_cache = {}

local function expand_value(value)
	if os.expand_env then
		local expanded = os.expand_env(value)
		if expanded and expanded ~= "" then
			return expanded
		end
	end
	local prev
	repeat
		prev = value
		value = value:gsub("%%([^%%]+)%%", function(name)
			return os.getenv(name) or ("%" .. name .. "%")
		end)
	until value == prev
	return value
end

local function env_dir_path(name)
	if not name then
		return nil
	end
	if name:lower() == "cd" then
		return os.getcwd and os.getcwd() or nil
	end
	local value = os.getenv(name)
	if not value or value == "" then
		return nil
	end
	value = expand_value(value)
	value = value:gsub('^"(.-)"$', "%1"):gsub("[/\\]+$", "")
	if value == "" or value:find("://", 1, true) or value:find(";", 1, true) then
		return nil
	end
	local ok_file, isfile = pcall(function()
		return os.isfile and os.isfile(value)
	end)
	if ok_file and isfile then
		return nil
	end
	local ok_dir, isdir = pcall(function()
		return os.isdir and os.isdir(value)
	end)
	if ok_dir and isdir then
		return value
	end
	return nil
end

local function is_dir_env(name)
	if not name then
		return false
	end
	local key = name:lower()
	local cached = dir_cache[key]
	if cached ~= nil then
		return cached
	end
	local result = env_dir_path(name) ~= nil
	dir_cache[key] = result
	return result
end

local function parse_percents(word)
	local in_out = false
	local index = nil
	for i = 1, #word do
		if word:sub(i, i) == "%" then
			in_out = not in_out
			if in_out then
				index = i - 1
			else
				index = i
			end
		end
	end
	return in_out, index
end

-- %NAME%\rel at the cursor. rel always starts with \ or /.
local function env_rel_from_line(line_state)
	local before = line_state:getline():sub(1, line_state:getcursor() - 1)
	before = before:gsub('"+$', ""):gsub("'+$", "")
	return before:match("%%([^%%]+)%%([/\\][^&|<>%s\"]*)$")
end

local function glob_entries(pattern)
	if os.globfiles then
		local ok, result = pcall(os.globfiles, pattern, true)
		if ok and type(result) == "table" then
			return result
		end
	end
	if os.glob then
		local ok, result = pcall(os.glob, pattern)
		if ok and type(result) == "table" then
			return result
		end
	end
	return {}
end

local function add_env_path_matches(match_builder, name, rel)
	local root = env_dir_path(name)
	if not root then
		return
	end

	local parent, prefix = rel:match("^(.*[/\\])([^/\\]*)$")
	if not parent then
		parent, prefix = rel, ""
	end

	local fs = (root .. parent):gsub("/", "\\"):gsub("\\+", "\\")
	if fs:sub(-1) ~= "\\" then
		fs = fs .. "\\"
	end

	for _, item in ipairs(glob_entries(fs .. prefix .. "*")) do
		local fname, ftype
		if type(item) == "table" then
			fname, ftype = item.name, item.type
		else
			fname = item
		end
		if fname then
			fname = fname:gsub("[/\\]+$", "")
			fname = fname:match("([^/\\]+)$") or fname
			if fname ~= "" and fname ~= "." and fname ~= ".." then
				local is_dir = ftype and ftype:find("dir", 1, true)
				if is_dir == nil then
					local ok, d = pcall(function()
						return os.isdir and os.isdir(fs .. fname)
					end)
					is_dir = ok and d
				end
				-- Use `/` in fzf display: a trailing `\` makes `cmd` eat the
				-- closing quote of `--preview "fzf-preview.cmd {}"`.
				local display = fname
				if is_dir then
					display = fname .. "/"
				end
				match_builder:addmatch({
					match = fname,
					type = ftype or (is_dir and "dir" or "file"),
					display = display,
				})
			end
		end
	end

	if match_builder.setvolatile then
		match_builder:setvolatile()
	end
end

local function add_env_names(match_builder)
	local names = {}
	local seen = {}
	local ok, listed = pcall(function()
		return os.getenvnames and os.getenvnames() or {}
	end)
	if ok then
		for _, name in ipairs(listed) do
			if name ~= "" and not seen[name:lower()] then
				seen[name:lower()] = true
				table.insert(names, name)
			end
		end
	end
	for _, name in ipairs(special_env_vars) do
		if not seen[name] then
			seen[name] = true
			table.insert(names, name)
		end
	end
	for _, name in ipairs(names) do
		local match = "%" .. name .. "%"
		if is_dir_env(name) then
			match = match .. "\\"
			match_builder:addmatch({
				match = match,
				type = "word",
				display = "%" .. name .. "%/",
			})
		else
			match_builder:addmatch(match, "word")
		end
	end
end

-- Priority 9 runs before Clink's built-in %VAR% generator (10).
local env_gen = clink.generator(9)

function env_gen:generate(line_state, match_builder)
	local name, rel = env_rel_from_line(line_state)
	if name and rel and is_dir_env(name) then
		add_env_path_matches(match_builder, name, rel)
		return true
	end

	local word = line_state:getendword()
	if word:sub(-1) ~= "%" then
		return false
	end

	if settings.get("match.expand_envvars") then
		local in_out = parse_percents(word)
		if not in_out then
			return false
		end
	end

	add_env_names(match_builder)
	match_builder:setsuppressappend()
	match_builder:setsuppressquoting()
	return true
end

function env_gen:getwordbreakinfo(line_state)
	local word = line_state:getendword()

	-- %VAR%\path: drop %VAR% (and the last slash) from the completable word so
	-- match.expand_envvars does not rewrite the line to an absolute path.
	local prefix, rel = word:match("^(%%[^%%]+%%)([/\\].*)$")
	if prefix and rel then
		local last_slash = word:find("[/\\][^/\\]*$")
		if last_slash then
			return last_slash, 0
		end
		return #prefix, 0
	end

	local in_out, index = parse_percents(word)
	if not index then
		return
	end
	-- %VAR% with no trailing path: keep the whole word so Clink can expand it.
	if not in_out and settings.get("match.expand_envvars") then
		return 0, #word
	end
	return index, (in_out and 1) or 0
end

if clink.onbeginedit then
	clink.onbeginedit(function()
		dir_cache = {}
	end)
end

local function should_remove_env_slash(line, cursor)
	if cursor <= 1 or line:sub(cursor - 1, cursor - 1) ~= "\\" then
		return false
	end
	local name = line:sub(1, cursor - 2):match("%%([^%%]+)%%$")
	return name and is_dir_env(name)
end

-- luacheck: globals envvar_insert_space
function envvar_insert_space(rl_buffer)
	local line = rl_buffer:getbuffer()
	local cursor = rl_buffer:getcursor()
	if should_remove_env_slash(line, cursor) then
		rl_buffer:remove(cursor - 1, cursor)
	end
	rl_buffer:insert(" ")
end

if rl.describemacro then
	rl.describemacro(
		"luafunc:envvar_insert_space",
		"Insert space; replace completion backslash after a directory %VAR%"
	)
end

local function apply_space_binding()
	if not rl.setbinding then
		return
	end
	for _, keymap in ipairs({ "emacs", "vi-insert" }) do
		rl.setbinding([[" "]], [["luafunc:envvar_insert_space"]], keymap)
	end
end

apply_space_binding()
if clink.onbeginedit then
	clink.onbeginedit(apply_space_binding)
end
