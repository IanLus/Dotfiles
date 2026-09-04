-- Shared by zsh (fzf/vgs-file.sh) and Clink (windows/clink/fzf-vgs.cmd).
--   list
--   path <porcelain-line>
--   preview <porcelain-line>
--   open <porcelain-line>
--   open-file <sel-file>

local is_win = package.config:sub(1, 1) == "\\"
local null = is_win and "nul" or "/dev/null"

local function porcelain_path(line)
	if not line or line == "" then
		return ""
	end
	line = line:gsub("\r$", ""):gsub("\27%[[0-9;]*m", "")
	if #line < 4 then
		return ""
	end
	local rest = line:sub(4)
	rest = rest:gsub(".* -> ", "")
	rest = rest:gsub('^"', ""):gsub('"$', ""):gsub('\\"', '"')
	return rest
end

local function quote_arg(s)
	s = tostring(s)
	if is_win then
		return '"' .. s:gsub('"', "") .. '"'
	end
	return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function has_cmd(name)
	local cmd = is_win and ("where " .. name .. " 2>" .. null) or ("command -v " .. name .. " 2>" .. null)
	local r = io.popen(cmd)
	if not r then
		return false
	end
	local line = r:read("*l")
	r:close()
	return line ~= nil and line ~= ""
end

local function is_tracked(file)
	local r = io.popen("git ls-files --error-unmatch -- " .. quote_arg(file) .. " 2>" .. null)
	if not r then
		return false
	end
	local line = r:read("*l")
	r:close()
	return line ~= nil and line ~= ""
end

local function run_preview(file)
	if file == "" then
		return
	end
	local diff
	if is_tracked(file) then
		diff = "git --no-pager diff HEAD --color=always -- " .. quote_arg(file)
	else
		diff = "git --no-pager diff --no-index --color=always -- /dev/null " .. quote_arg(file)
	end
	if has_cmd("delta") then
		os.execute(diff .. " | delta --paging=never")
	else
		os.execute(diff)
	end
end

local function open_editor(file)
	if file == "" then
		os.exit(1)
	end
	local editor = os.getenv("EDITOR") or os.getenv("VISUAL") or "nvim"
	os.execute(editor .. " -- " .. quote_arg(file))
end

local function read_first_line(path)
	local f = io.open(path, "r")
	if not f then
		return ""
	end
	local line = f:read("*l") or ""
	f:close()
	return line
end

local action = arg and arg[1]
local rest = table.concat(arg or {}, " ", 2)

if action == "list" then
	os.execute("git -c core.quotePath=false status --porcelain=v1")
elseif action == "path" then
	io.stdout:write(porcelain_path(rest) .. "\n")
elseif action == "preview" then
	run_preview(porcelain_path(rest))
elseif action == "open" then
	open_editor(porcelain_path(rest))
elseif action == "open-file" then
	if rest == "" then
		os.exit(1)
	end
	open_editor(porcelain_path(read_first_line(rest)))
else
	io.stderr:write("usage: vgs.lua list|path|preview|open <line>|open-file <sel>\n")
	os.exit(2)
end
