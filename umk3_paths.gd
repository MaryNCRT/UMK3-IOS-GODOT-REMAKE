## Where the game data is.
##
## **First choice is the copy inside the project**, at `res://assets/game`, put
## there by umk3_bundle.gd: the 187 files this build actually uses, followed
## from the stages' own references rather than copied wholesale. With it the
## project runs on its own -- no install path, no first-run prompt, no argument
## -- which is what makes it something two people can open and work on.
##
## That copy is the user's own data and `.gitignore` excludes `assets/`, so it
## stays local. A checkout without it still works the old way: pass the path to
## an extracted `UMK3.app/res` once and it is remembered in `user://umk3.cfg`,
## which is outside the project.
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
## The bundled copy, when it is there.
const BUNDLED := "res://assets/game"


static func resolve(current: String = "") -> String:
	var tries: Array[String] = []
	# **The bundle wins**, ahead of anything remembered or passed in: a project
	# that carries its data should not quietly read someone else's install
	# because a stale path in user:// happens to still be valid.
	if is_valid(BUNDLED):
		return BUNDLED
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
