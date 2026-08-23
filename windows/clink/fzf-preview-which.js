// On-demand Clink `which` for a single fzf preview item.
// Does not scan or cache all aliases at CMD startup.

var name = WScript.Arguments.length ? WScript.Arguments(0) : "";
if (!name) {
	WScript.Quit(1);
}

var fso = new ActiveXObject("Scripting.FileSystemObject");
var sh = new ActiveXObject("WScript.Shell");
var profile = sh.ExpandEnvironmentStrings("%CLINK_PROFILE%");
if (!profile || profile === "%CLINK_PROFILE%") {
	profile = fso.GetParentFolderName(WScript.ScriptFullName);
}
profile = profile.replace(/\\+$/, "");

var builtins = {
	assoc: 1, "break": 1, call: 1, cd: 1, chdir: 1, cls: 1, color: 1, copy: 1,
	date: 1, del: 1, dir: 1, dpath: 1, echo: 1, endlocal: 1, erase: 1, exit: 1,
	"for": 1, ftype: 1, "goto": 1, "if": 1, keys: 1, md: 1, mkdir: 1, mklink: 1,
	move: 1, path: 1, pause: 1, popd: 1, prompt: 1, pushd: 1, rd: 1, rem: 1,
	ren: 1, rename: 1, rmdir: 1, "set": 1, setlocal: 1, shift: 1, start: 1,
	time: 1, title: 1, type: 1, ver: 1, verify: 1, vol: 1
};

function readFile(path) {
	if (!fso.FileExists(path)) {
		return "";
	}
	var fh = fso.OpenTextFile(path, 1);
	var text = fh.AtEndOfStream ? "" : fh.ReadAll();
	fh.Close();
	return text;
}

function escapeRe(s) {
	return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function isLuaCommand(cmd) {
	var dir = profile + "\\functions";
	if (!fso.FolderExists(dir)) {
		return false;
	}
	var needle = 'register_clink_lua_command("' + cmd + '")';
	var files = new Enumerator(fso.GetFolder(dir).Files);
	for (; !files.atEnd(); files.moveNext()) {
		var file = files.item();
		if (fso.GetExtensionName(file.Name).toLowerCase() !== "lua") {
			continue;
		}
		if (readFile(file.Path).toLowerCase().indexOf(needle.toLowerCase()) >= 0) {
			return true;
		}
	}
	return false;
}

function getAliasExpansion(cmd) {
	var text = readFile(profile + "\\aliases\\aliases.lua");
	if (!text) {
		return null;
	}
	var re = new RegExp('os\\.setalias\\("' + escapeRe(cmd) + '"\\s*,\\s*"([^"]*)"', "i");
	var m = text.match(re);
	return m ? m[1] : null;
}

function firstToken(expansion) {
	expansion = expansion.replace(/^\s+/, "");
	var quoted = expansion.match(/^"([^"]+)"/);
	if (quoted) {
		return quoted[1];
	}
	var tok = expansion.match(/^(\S+)/);
	return tok ? tok[1] : expansion;
}

function wherePaths(cmd) {
	var paths = [];
	var proc = sh.Exec("where.exe \"" + cmd.replace(/"/g, "") + "\"");
	while (!proc.StdOut.AtEndOfStream) {
		var line = proc.StdOut.ReadLine();
		if (line) {
			paths.push(line);
		}
	}
	while (!proc.StdErr.AtEndOfStream) {
		proc.StdErr.ReadLine();
	}
	proc.StdOut.Close();
	return paths;
}

function resolve(cmd, seen) {
	var key = cmd.toLowerCase();
	seen = seen || {};
	if (seen[key]) {
		return cmd;
	}
	seen[key] = true;

	if (isLuaCommand(cmd)) {
		return cmd + " (Clink Lua command)";
	}

	var expansion = getAliasExpansion(cmd);
	if (expansion) {
		return resolve(firstToken(expansion), seen);
	}

	if (builtins[key]) {
		return cmd + " (CMD internal command)";
	}

	var paths = wherePaths(cmd);
	if (paths.length) {
		return paths[0];
	}
	return cmd;
}

if (isLuaCommand(name)) {
	WScript.Echo(name + ": Clink Lua command");
	WScript.Quit(0);
}

var expansion = getAliasExpansion(name);
if (expansion) {
	WScript.Echo(name + ": Alias for (" + resolve(name) + ")");
	WScript.Quit(0);
}

if (builtins[name.toLowerCase()]) {
	WScript.Echo(name + ": CMD internal command");
	WScript.Quit(0);
}

var paths = wherePaths(name);
if (paths.length) {
	for (var i = 0; i < paths.length; i++) {
		WScript.Echo(paths[i]);
	}
	WScript.Quit(0);
}

WScript.Quit(1);
