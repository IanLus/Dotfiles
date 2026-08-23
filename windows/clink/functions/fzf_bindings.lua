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
	-- %VAR%\rel → only the last relative component (not DOTDIR\).
	local env_rel = word:match("^%%[^%%]+%%[\\/](.*)$")
	if env_rel then
		word = env_rel:match("([^/\\]*)$") or env_rel
	else
		word = word:gsub("%%", "")
	end
	word = word:gsub("%^", "^^")
	local pre, suf = word:match("^(.-)(\\*)$")
	if pre and suf then
		word = pre .. suf .. suf
	end
	return word
end

-- luacheck: globals fzf_complete_force fzf_complete_with_query
function fzf_complete_with_query(rl_buffer, line_state)
	if not fzf_complete_force then
		rl.invokecommand("complete")
		return
	end

	local prev = os.getenv("FZF_COMPLETION_OPTS") or ""
	local word = word_at_cursor(line_state)
	if word ~= "" then
		os.setenv("FZF_COMPLETION_OPTS", prev .. ' --query "' .. word .. '"')
	end

	local ok, err = pcall(fzf_complete_force, rl_buffer, line_state)
	os.setenv("FZF_COMPLETION_OPTS", prev)
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
