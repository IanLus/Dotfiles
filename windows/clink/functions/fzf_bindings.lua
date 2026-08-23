-- clink-fzf applies default bindings in onbeginedit (not at load).
-- Alt+B -> bash backward-word.
-- "\e?" (Alt+Shift+/) -> binding picker; replaces Clink's clink-what-is.
-- Tab / Ctrl+Space -> fzf_complete_force, with the current word as --query.

if not rl.setbinding then
	return
end

-- Same extraction as clink-fzf get_word_at_cursor (local, not exported).
local function word_at_cursor(line_state)
	if not line_state or line_state:getwordcount() <= 0 then
		return ""
	end
	local info = line_state:getwordinfo(line_state:getwordcount())
	if not info then
		return ""
	end
	local word = line_state:getline():sub(info.offset, line_state:getcursor() - 1)
	word = word:gsub('"', ""):gsub("'", "")
	-- Query is only the last path component, so `cd windows\<Tab>` does not
	-- prefill `windows\` (candidates are shown relative to that directory).
	local env_rel = word:match("^%%[^%%]+%%[\\/](.*)$")
	if env_rel then
		word = env_rel:match("([^/\\]*)$") or env_rel
	elseif word:find("[/\\]") then
		word = word:match("([^/\\]*)$") or ""
	else
		word = word:gsub("%%", "")
	end
	word = word:gsub("%^", "^^")
	return word
end

-- Directory prefix of the current word (`windows\` → `windows`), with %VAR% expanded.
local function completion_dir(line_state)
	if not line_state or line_state:getwordcount() <= 0 then
		return ""
	end
	local info = line_state:getwordinfo(line_state:getwordcount())
	if not info then
		return ""
	end
	local word = line_state:getline():sub(info.offset, line_state:getcursor() - 1)
	word = word:gsub('"', ""):gsub("'", "")
	local dir = word:match("^(.*)[/\\][^/\\]*$")
	if not dir or dir == "" then
		return ""
	end
	if os.expand_env then
		dir = os.expand_env(dir) or dir
	end
	return dir
end

-- Show file/dir matches as names relative to the typed directory, not pwd.
local function relativize_path_display(matches)
	if type(matches) ~= "table" then
		return matches
	end
	for _, m in ipairs(matches) do
		if type(m) == "table" and type(m.match) == "string" and m.match:find("[/\\]") then
			local name = m.match:gsub("[/\\]+$", ""):match("([^/\\]+)$")
			if name and name ~= "" then
				local is_dir = (type(m.type) == "string" and m.type:find("dir", 1, true))
					or m.match:find("[/\\]$")
				m.display = is_dir and (name .. "\\") or name
			end
		end
	end
	return matches
end

local disp_gen = clink.generator(1)
function disp_gen:generate() -- luacheck: no unused
	if clink.onfiltermatches then
		clink.onfiltermatches(relativize_path_display)
	end
	return false
end

-- luacheck: globals fzf_complete_force fzf_complete_with_query
function fzf_complete_with_query(rl_buffer, line_state)
	if not fzf_complete_force then
		rl.invokecommand("complete")
		return
	end

	local prev = os.getenv("FZF_COMPLETION_OPTS") or ""
	local prev_prefix = os.getenv("CLINK_FZF_PATH_PREFIX")
	local word = word_at_cursor(line_state)
	local prefix = completion_dir(line_state)
	if prefix ~= "" then
		os.setenv("CLINK_FZF_PATH_PREFIX", prefix)
	else
		os.setenv("CLINK_FZF_PATH_PREFIX", nil)
	end
	if word ~= "" then
		os.setenv("FZF_COMPLETION_OPTS", prev .. ' --query "' .. word .. '"')
	end

	local ok, err = pcall(fzf_complete_force, rl_buffer, line_state)
	os.setenv("FZF_COMPLETION_OPTS", prev)
	if prev_prefix == nil or prev_prefix == "" then
		os.setenv("CLINK_FZF_PATH_PREFIX", nil)
	else
		os.setenv("CLINK_FZF_PATH_PREFIX", prev_prefix)
	end
	if not ok then
		error(err)
	end
end

if rl.describemacro then
	rl.describemacro(
		"luafunc:fzf_complete_with_query",
		"Use fzf for completion; prefill the query with the current word"
	)
end

local function apply_fzf_binding_overrides()
	for _, keymap in ipairs({ "emacs", "vi-command", "vi-insert" }) do
		rl.setbinding([["\e?"]], [["luafunc:fzf_bindings"]], keymap)
		rl.setbinding([["\M-b"]], "backward-word", keymap)
		rl.setbinding([["\t"]], [["luafunc:fzf_complete_with_query"]], keymap)
		rl.setbinding([["\e[27;5;32~"]], [["luafunc:fzf_complete_with_query"]], keymap)
	end
end

clink.onbeginedit(apply_fzf_binding_overrides)
