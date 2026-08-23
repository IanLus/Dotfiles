-- Register onfilterinput Lua commands as doskey aliases so Clink colors them
-- with color.doskey (same as other aliases) and includes them in command completion.

clink_lua_commands = clink_lua_commands or {}

---Register a Lua command for doskey coloring + completion.
---@param name string
function register_clink_lua_command(name)
	if not name or name == "" then
		return
	end
	clink_lua_commands[name:lower()] = name
	-- Expansion is never run: onfilterinput consumes these commands first.
	-- Using `rem` keeps a harmless fallback if filtering is skipped.
	if os.setalias then
		os.setalias(name, "rem $*")
	end
end
