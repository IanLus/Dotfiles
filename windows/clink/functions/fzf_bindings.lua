-- clink-fzf applies default bindings in onbeginedit (not at load).
-- Alt+B -> bash backward-word.
-- "\e?" (Alt+Shift+/) -> binding picker; replaces Clink's clink-what-is.
-- Tab / Ctrl+Space -> fzf over matches; last path component as --query.
-- / in the fzf window: fzf-tab continuous-trigger — accept and complete again.
--
-- This script runs fzf itself with --expect=/. execute-silent on Windows either
-- breaks the command line or only runs +accept, so Lua never sees "continue".
-- clink-fzf's filter_matches also discards the expect line.

if not rl.setbinding then
	return
end

local intercept = false
local want_more = false
local pending_query = ""
local selected_match_text = nil

local function join_str(a, b)
	if not a or a == "" then
		return b or ""
	end
	if not b or b == "" then
		return a
	end
	return a .. " " .. b
end

local function get_fzf_complete_command(extra)
	local command = settings.get("fzf.exe_location")
	if not command or command == "" then
		command = "fzf.exe"
	end
	command = '"' .. command:gsub('"', "") .. '"'
	local height = settings.get("fzf.height")
	if height and height ~= "" then
		command = join_str(command, "--height " .. height)
	end
	command = join_str(command, "--reverse")
	command = join_str(command, os.getenv("FZF_DEFAULT_OPTS"))
	command = join_str(command, os.getenv("FZF_COMPLETION_OPTS") or os.getenv("FZF_COMPLETE_OPTS"))
	return join_str(command, extra)
end

-- Word being completed: text, 1-based [start, cursor), full line.
local function current_word_info(rl_buffer)
	local line = rl_buffer:getbuffer()
	local cursor = rl_buffer:getcursor()
	local before = line:sub(1, cursor - 1)
	local qstart = before:match('.*()"[^"]*$')
	local start
	if qstart then
		start = qstart + 1
	else
		start = before:match("()[^%s]*$") or cursor
	end
	local word = line:sub(start, cursor - 1):gsub('"', ""):gsub("'", "")
	return word, start, cursor, line
end

-- Query is only the last path component, so `cd windows\<Tab>` does not
-- prefill `windows\` (candidates are shown relative to that directory).
local function query_from_word(word)
	local env_rel = word:match("^%%[^%%]+%%[\\/](.*)$")
	if env_rel then
		word = env_rel:match("([^/\\]*)$") or env_rel
	elseif word:find("[/\\]") then
		word = word:match("([^/\\]*)$") or ""
	else
		word = word:gsub("%%", "")
	end
	return word:gsub("%^", "^^")
end

-- Directory prefix of the current word (`windows\` → `windows`), with %VAR% expanded.
local function prefix_from_word(word)
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

local function token_is_dir(token)
	if not token or token == "" then
		return false
	end
	local path = token
	if os.expand_env then
		path = os.expand_env(token) or token
	end
	path = path:gsub('^"(.-)"$', "%1"):gsub("[/\\]+$", "")
	if path == "" then
		return false
	end
	local ok, isdir = pcall(function()
		return os.isdir and os.isdir(path)
	end)
	return ok and isdir
end

local function buffer_len(rl_buffer)
	if rl_buffer.getlength then
		return rl_buffer:getlength()
	end
	return #rl_buffer:getbuffer()
end

-- Nested `complete` + fzf --height can leave the input looking like only the
-- last selected name (`windows`, then `clink`). Rebuild from the line as it
-- was before that `complete`, replacing just the current word.
local function apply_selected_word(rl_buffer, snapshot, match_text)
	if not match_text or match_text == "" or not snapshot then
		return
	end
	local prefix = snapshot.line:sub(1, snapshot.word_start - 1)
	local suffix = snapshot.line:sub(snapshot.word_end)
	local new_line = prefix .. match_text .. suffix
	local new_cursor = #prefix + #match_text + 1
	if rl_buffer:getbuffer() == new_line then
		rl_buffer:setcursor(new_cursor)
		return
	end
	rl_buffer:beginundogroup()
	rl_buffer:remove(1, buffer_len(rl_buffer) + 1)
	rl_buffer:setcursor(1)
	rl_buffer:insert(new_line)
	rl_buffer:setcursor(new_cursor)
	rl_buffer:endundogroup()
end

-- After accept: directory → `\`; file → space (fzf-tab continuous-trigger).
local function after_accept(rl_buffer)
	local line = rl_buffer:getbuffer()
	local cursor = rl_buffer:getcursor()
	local before = line:sub(1, cursor - 1)
	if before:match("[/\\]$") then
		return
	end
	local token = before:match('"([^"]*)"$') or before:match("([^%s]+)$") or ""
	if token_is_dir(token) then
		rl_buffer:insert("\\")
		return
	end
	if not before:match("%s$") then
		rl_buffer:insert(" ")
	end
end

local function strip_cr(s)
	return (s:gsub("\r$", ""))
end

local function match_label(m)
	if m.display and console.plaintext then
		return console.plaintext(m.display)
	end
	return m.match
end

-- Own fzf so we can read --expect=/ (clink-fzf's filter_matches discards that line).
local function run_fzf(matches)
	if not intercept then
		return matches
	end
	if type(matches) ~= "table" or #matches <= 1 then
		intercept = false
		return matches
	end

	local show_descriptions = settings.get("fzf.show_descriptions")
	local strings = {}
	local longest = 0
	for _, m in ipairs(matches) do
		local s = match_label(m)
		strings[#strings + 1] = s
		if show_descriptions and console.cellcount then
			local cells = console.cellcount(s)
			if longest < cells then
				longest = cells
			end
		end
	end

	local extra = "--expect=/"
	if pending_query ~= "" then
		extra = extra .. ' --query "' .. pending_query:gsub('"', "") .. '"'
	end
	local r, w = io.popenrw('"' .. get_fzf_complete_command(extra) .. '"')
	if not r or not w then
		intercept = false
		return matches
	end

	local which = {}
	for i, m in ipairs(matches) do
		local text = strings[i]
		if show_descriptions and m.description and m.description ~= "" then
			local desc = console.plaintext and console.plaintext(m.description) or m.description
			local pad = 4
			if console.cellcount then
				pad = longest + 4 - console.cellcount(text)
			end
			if pad < 1 then
				pad = 1
			end
			text = text .. string.rep(" ", pad) .. desc
		end
		local plain = console.plaintext and console.plaintext(text) or text
		if not which[plain] then
			which[plain] = m
		end
		w:write(text .. "\n")
	end
	w:close()

	local ret = {}
	local expect_line = r:read("*line")
	if expect_line then
		expect_line = strip_cr(expect_line)
		if expect_line == "/" then
			want_more = true
		elseif expect_line ~= "" then
			local m = which[expect_line]
			if m then
				ret[#ret + 1] = m
			end
		end
		while true do
			local line = r:read("*line")
			if not line then
				break
			end
			local m = which[strip_cr(line)]
			if m then
				ret[#ret + 1] = m
			end
		end
	end
	r:close()
	intercept = false
	if #ret == 0 then
		want_more = false
		selected_match_text = nil
	else
		selected_match_text = ret[1].match
	end
	return ret
end

local disp_gen = clink.generator(1)
function disp_gen:generate() -- luacheck: no unused
	if not clink.onfiltermatches then
		return false
	end
	clink.onfiltermatches(relativize_path_display)
	if intercept then
		clink.onfiltermatches(function(matches)
			clink.onfiltermatches(run_fzf)
			return matches
		end)
	end
	return false
end

local function line_state_word(line_state)
	if not line_state or line_state:getwordcount() <= 0 then
		return ""
	end
	local info = line_state:getwordinfo(line_state:getwordcount())
	if not info then
		return ""
	end
	local word = line_state:getline():sub(info.offset, line_state:getcursor() - 1)
	return (word or ""):gsub('"', ""):gsub("'", "")
end

local function ends_with_globstar(line_state, rl_buffer)
	local word = current_word_info(rl_buffer)
	local from_state = line_state_word(line_state)
	return from_state:sub(-2) == "**" or word:sub(-2) == "**"
end

local function restore_path_prefix(prev)
	if prev == nil or prev == "" then
		os.setenv("CLINK_FZF_PATH_PREFIX", nil)
	else
		os.setenv("CLINK_FZF_PATH_PREFIX", prev)
	end
end

local function run_continuous_loop(rl_buffer)
	while true do
		local word, word_start, word_end, line = current_word_info(rl_buffer)
		pending_query = query_from_word(word)
		local prefix = prefix_from_word(word)
		if prefix ~= "" then
			os.setenv("CLINK_FZF_PATH_PREFIX", prefix)
		else
			os.setenv("CLINK_FZF_PATH_PREFIX", nil)
		end

		intercept = true
		want_more = false
		selected_match_text = nil
		rl.invokecommand("complete")
		if intercept then
			rl_buffer:ding()
			intercept = false
			return
		end
		if selected_match_text then
			apply_selected_word(rl_buffer, {
				line = line,
				word_start = word_start,
				word_end = word_end,
			}, selected_match_text)
			after_accept(rl_buffer)
		end
		if not want_more then
			return
		end
		-- fzf --height leaves the prompt looking like the last name until redraw.
		if rl_buffer.refreshline then
			rl_buffer:refreshline()
		end
	end
end

-- luacheck: globals fzf_complete_force fzf_complete_with_query
function fzf_complete_with_query(rl_buffer, line_state)
	-- `**` recursive listing lives in clink-fzf. Call the function directly:
	-- `rl.invokecommand("luafunc:...")` from inside a luafunc does not run it.
	if fzf_complete_force and ends_with_globstar(line_state, rl_buffer) then
		fzf_complete_force(rl_buffer, line_state)
		return
	end

	if not io.popenrw then
		rl.invokecommand("complete")
		return
	end

	local prev_prefix = os.getenv("CLINK_FZF_PATH_PREFIX")
	local ok, err = pcall(run_continuous_loop, rl_buffer)
	restore_path_prefix(prev_prefix)
	if rl_buffer.refreshline then
		rl_buffer:refreshline()
	end
	if not ok then
		error(err)
	end
end

if rl.describemacro then
	rl.describemacro(
		"luafunc:fzf_complete_with_query",
		"Use fzf for completion; / accepts and continues (dir=descend, file=next from cwd)"
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
