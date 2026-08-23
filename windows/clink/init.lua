-- Clink only auto-loads *.lua in the profile root (not subdirectories).
-- This loader pulls in aliases/ and functions/.

local src = debug.getinfo(1, "S").source
if src:sub(1, 1) == "@" then
	src = src:sub(2)
end
local root = src:match("^(.*)[/\\]") or "."

local scripts = {
	"aliases\\init.lua",
	"functions\\utf8_console.lua",
	"functions\\lua_commands.lua",
	"functions\\fzf_env.lua",
	"functions\\fzf_bindings.lua",
	"functions\\envvar_complete.lua",
	"functions\\fnm.lua",
	"functions\\unix_tools.lua",
	"functions\\fs.lua",
	"functions\\which.lua",
	"functions\\proxy.lua",
}

for _, rel in ipairs(scripts) do
	local path = root .. "\\" .. rel
	local fn, err = loadfile(path)
	if not fn then
		print("Failed to load " .. path .. ": " .. tostring(err))
	else
		local ok, run_err = pcall(fn)
		if not ok then
			print("Error running " .. path .. ": " .. tostring(run_err))
		end
	end
end
