## Copy the game files this project actually uses into the project.
##
##     godot --headless --path <project> --script umk3/umk3_bundle.gd \
##           -- <res dir> [NAME ...]
##
## Run it again with extra names to bring one more thing in as it is needed --
## another character, another file group. It only copies what is missing, so
## adding SUBZERO_STANDARD costs the eleven files SUBZERO_STANDARD needs and
## nothing else.
##
## After this the build runs on its own: no `UMK3.app`, no remembered path, no
## first-run prompt. Everything is under `res://assets/game/`, laid out the way
## the game lays it out, so every reader keeps working unchanged.
##
## ## Which files, and how it knows
##
## Not a copy of `res/` -- that is 1.4 GB and most of it is characters and
## fatalities this build never touches. It **follows the references**:
##
##     the eleven stages         .meshset, .scene, .events
##     what their meshes name    every texture, through the engine's own
##                               search order (Textures/ first, then the root)
##     what their events name    the effect groups, and those groups' textures
##     the character             .bones, .skin, .skinanim, .meshset, its texture
##     the frame list            which is also what a valid `res` is probed by
##     the front end             the four sheets the menu draws
##     the sound groups          the 25 names recovered from __cstring
##     the stage music           one mp3 each
##
## Anything it cannot find is reported by name rather than skipped quietly: a
## missing file here becomes a missing texture at run time, and the difference
## between "not copied" and "not there" is worth knowing at the moment of
## copying.
##
## ## This is the user's own data, and it stays local
##
## `.gitignore` excludes `assets/`, so none of it can reach the repository. What
## this changes is only that a copy lives next to the project instead of being
## read out of an install path -- which is what makes the thing shareable as a
## working folder without shipping a data dependency along with it.
extends SceneTree

const _MeshSet := preload("res://umk3/umk3_meshset.gd")
const _Events := preload("res://umk3/umk3_events.gd")
const _Audio := preload("res://umk3/umk3_audio.gd")
const _StageList := preload("res://umk3/umk3_stagelist.gd")

const OUT := "res://assets/game"

## The character this build fights with, and the front-end art the menu draws.
const CHARACTER := "SCORPION_STANDARD"
const FRAME_LIST := "framelists/scorpionframes.txt"
const FE_SHEETS := ["FE_TITLE_BG", "FE_MAINLOGO_EN", "FE_MENU_PLAY",
	"FE_BUTTONS_01", "FE_BG_MARBLE"]

## The spear, and Scorpion's fire.
##
## **These are named in the binary, not in any file group**, which is why
## following the meshsets never brought them in. `RenderExtras` (0x00020fa8)
## walks two players' worth of `_SpearStartPos` / `_SpearEndPos` and draws the
## rope out of `_SpearTexture[0..2]`, picking one by `_SpearWhichTexture[p] % 3`
## -- so SPEAR1, SPEAR2 and SPEAR3 are the rope's three frames and SPEAR4 is
## the head. There is no spear MESH anywhere in the game: it is a sprite.
##
## SCORPFIRE and FLAME1..3 are the fire that goes with him.
const EXTRA_TEXTURES := ["SPEAR1", "SPEAR2", "SPEAR3", "SPEAR4",
	"SCORPFIRE", "FLAME1", "FLAME2", "FLAME3", "HUD_TPAGE",
	"SCORPION_DIFFUSE2", "BLOODNEW"]

var res_dir := ""
var _want := {}            ## relative path -> true
var _missing: Array[String] = []
var _copied := 0
var _bytes := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: ... --script umk3/umk3_bundle.gd -- <path to UMK3.app/res>")
		quit(2)
		return
	res_dir = args[0]
	var extra := args.slice(1)
	if not FileAccess.file_exists(res_dir.path_join(FRAME_LIST)):
		printerr("%s does not hold %s -- is that the res folder?"
			% [res_dir, FRAME_LIST])
		quit(2)
		return

	_want[FRAME_LIST] = true

	for stem in _StageList.STAGES:
		_stage(stem)
	_character(CHARACTER)
	for sheet in FE_SHEETS:
		_texture(sheet)
	for tex in EXTRA_TEXTURES:
		_texture(tex)
	_sounds()

	# Whatever else was asked for. A name with a `.bones` beside it is a
	# character and needs its skin and its animation; anything else is an
	# ordinary file group.
	for name in extra:
		if FileAccess.file_exists(res_dir.path_join(name + ".bones")):
			_character(name)
			var who := name.get_slice("_", 0).to_lower()
			_add("framelists/" + who + "frames.txt")
		else:
			_group(name, true)

	# Only what is not already here: running this again to add one character
	# should cost one character.
	var todo: Array[String] = []
	for rel in _want.keys():
		if not FileAccess.file_exists(OUT.path_join(rel)):
			todo.append(rel)
	print("%d files referenced, %d not here yet" % [_want.size(), todo.size()])
	for rel in todo:
		_copy(rel)

	print("\ncopied %d files, %.1f MB, into %s" % [_copied, _bytes / 1048576.0, OUT])
	if not _missing.is_empty():
		print("MISSING (%d):" % _missing.size())
		for m in _missing:
			print("   " + m)
	quit(0 if _missing.is_empty() else 1)


# ------------------------------------------------------------------ gathering
func _add(rel: String) -> bool:
	if rel == "":
		return false
	if _want.has(rel):
		return true
	if not FileAccess.file_exists(res_dir.path_join(rel)):
		return false
	_want[rel] = true
	return true


## A texture, through the engine's own search order.
func _texture(mesh_texture: String) -> void:
	if mesh_texture == "" or mesh_texture.begins_with("NOTEXTURE"):
		return
	var stem := mesh_texture
	var dot := stem.rfind(".")
	if dot >= 0:
		stem = stem.substr(0, dot)
	for ext in [".pvr", ".PVR", ".PNG", ".png"]:
		if _add("Textures/" + stem + ext) or _add(stem + ext):
			return
	_missing.append("texture " + stem)


## One file group: its meshes' textures, and the effects its events name.
func _group(stem: String, with_events: bool) -> void:
	var ms := _MeshSet.new()
	if ms.load_file(res_dir.path_join(stem + ".meshset")):
		_add(stem + ".meshset")
		for m in ms.meshes:
			_texture(m.texture)
	else:
		_missing.append(stem + ".meshset")
	_add(stem + ".scene")

	if not with_events:
		return
	_add(stem + ".events")
	var ev := _Events.new()
	if not ev.load_file(res_dir.path_join(stem + ".events")):
		return
	for tr in ev.tracks:
		if tr.name != "":
			# The track name is the effect's file group, upper-cased.
			_group(tr.name.to_upper(), false)


func _stage(stem: String) -> void:
	_group(stem, true)


func _character(stem: String) -> void:
	for ext in [".bones", ".skin", ".skinanim"]:
		if not _add(stem + ext):
			_missing.append(stem + ext)
	_group(stem, false)


func _sounds() -> void:
	for g in [_Audio.GRP_FOOT, _Audio.GRP_BLOCK, _Audio.GRP_FACE, _Audio.GRP_BIG3,
			_Audio.GRP_BIG12, _Audio.GRP_BODY, _Audio.GRP_WHOOSH,
			_Audio.GRP_BWHOOSH, _Audio.GRP_FALL, _Audio.GRP_SCORP,
			_Audio.GRP_STAB, _Audio.GRP_KLANG, _Audio.VOICE_ATTACK,
			_Audio.VOICE_JUMP, _Audio.VOICE_FACE, _Audio.VOICE_BODY,
			_Audio.VOICE_WASTED, _Audio.VOICE_RUN, _Audio.VOICE_GRAB,
			_Audio.VOICE_DEATH, _Audio.VOICE_TRIP]:
		for name in g:
			if not _add("audio/" + name + ".wav"):
				_missing.append("audio/" + name + ".wav")
	for stem in _StageList.MUSIC:
		# The music list repeats -- two stages share Church -- so the set does
		# the work and nothing is copied twice.
		if not _add("audio/" + stem + ".mp3"):
			_missing.append("audio/" + stem + ".mp3")


# ------------------------------------------------------------------- copying
func _copy(rel: String) -> void:
	var src := res_dir.path_join(rel)
	var dst := OUT.path_join(rel)
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())

	var f := FileAccess.open(src, FileAccess.READ)
	if f == null:
		_missing.append(rel)
		return
	var d := f.get_buffer(f.get_length())
	f.close()

	var o := FileAccess.open(dst, FileAccess.WRITE)
	if o == null:
		_missing.append("could not write " + dst)
		return
	o.store_buffer(d)
	o.close()
	_copied += 1
	_bytes += d.size()
