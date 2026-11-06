-- Shared by zsh (fzf/vgs-file.sh) and Clink (windows/clink/fzf-vgs.cmd).
--   list
--   path <porcelain-line>
--   preview <porcelain-line>
--   open <porcelain-line>
--   open-file <sel-file>

local is_win = package.config:sub(1, 1) == "\\"
local null = is_win and "nul" or "/dev/null"
local sep = is_win and "\\" or "/"

local function quote_arg(s)
	s = tostring(s)
	if is_win then
		return '"' .. s:gsub('"', "") .. '"'
	end
	return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- git status 给的是相对仓库根的路径，而脚本可能在子目录里跑。
-- 所有 git 操作统一 -C 到仓库根，打开文件则用绝对路径。
local _root
local function repo_root()
	if _root then
		return _root
	end
	_root = ""
	local r = io.popen("git rev-parse --show-toplevel 2>" .. null)
	if r then
		local line = r:read("*l") or ""
		r:close()
		line = line:gsub("\r$", "")
		if line ~= "" then
			_root = line
		end
	end
	return _root
end

-- 加上 -C <仓库根>，让 root 相对路径在任何子目录下都能命中
local function git_in_root(sub)
	local root = repo_root()
	if root == "" then
		return "git " .. sub
	end
	return "git -C " .. quote_arg(root) .. " " .. sub
end

local function abs_path(file)
	if file == "" then
		return ""
	end
	if file:sub(1, 1) == "/" or file:match("^%a:[/\\]") then
		return file
	end
	local root = repo_root()
	if root == "" then
		return file
	end
	return root .. sep .. file
end

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
	local r = io.popen(git_in_root("ls-files --error-unmatch -- " .. quote_arg(file) .. " 2>" .. null))
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
		-- 仓库根相对路径，配 -C <root> 才在子目录里也找得到
		diff = git_in_root("--no-pager diff HEAD --color=always -- " .. quote_arg(file))
	else
		-- 未跟踪文件给绝对路径，--no-index 不吃仓库根相对路径
		diff = git_in_root("--no-pager diff --no-index --color=always -- /dev/null " .. quote_arg(abs_path(file)))
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
	-- 编辑器在调用者的 cwd（可能是子目录）里跑，必须给绝对路径
	os.execute(editor .. " -- " .. quote_arg(abs_path(file)))
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
	os.execute(git_in_root("-c core.quotePath=false status --porcelain=v1"))
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
