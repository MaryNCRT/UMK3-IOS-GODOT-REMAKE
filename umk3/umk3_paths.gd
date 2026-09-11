## Where the game data is, remembered between runs.
##
## The project ships NO GAME DATA. Every run needs the path to the user's own
## extracted `UMK3.app/res`, and asking for it on the command line every time
## makes the project unusable from the editor's Play button -- and from the
## Godot MCP server, which launches without arguments.
##
## So the first path that works is written to `user://umk3.cfg` and reused.
## `user://` is outside the project, so nothing about the user's install ends
## up in the repository.
extends RefCounted

const CFG := "user://umk3.cfg"

## A folder is only accepted if a file deep inside it is really there. Probing
## for the directory alone accepts a half-copied `res` and then fails much
## later with "no .bones", which is a much worse error to debug.
const PROBE := "framelists/scorpionframes.txt"


static func is_valid(dir: String) -> bool:
	return dir != "" and FileAccess.file_exists(dir.path_join(PROBE))


static func remember(dir: String) -> void:
	var c := ConfigFile.new()
	c.set_value("umk3", "res_dir", dir)
	c.save(CFG)


static func recall() -> String:
	var c := ConfigFile.new()
	if c.load(CFG) != OK:
		return ""
	return str(c.get_value("umk3", "res_dir", ""))


## In order: what the caller already has, the command line, the saved value.
## The first one that passes the probe wins and is saved.
static func resolve(current: String = "") -> String:
	var tries: Array[String] = []
	if current != "":
		tries.append(current)
	for a in OS.get_cmdline_user_args():
		if a != "":
			tries.append(a)
	var saved := recall()
	if saved != "":
		tries.append(saved)

	for t in tries:
		if is_valid(t):
			if t != saved:
				remember(t)
			return t

	# Nothing valid. Say which were tried rather than just failing.
	if not tries.is_empty():
		push_warning("[umk3] none of these hold " + PROBE + ": "
			+ ", ".join(tries))
	return ""
