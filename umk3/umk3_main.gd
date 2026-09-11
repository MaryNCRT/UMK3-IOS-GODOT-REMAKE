## The shell: the menu, and the stage it launches.
##
## The same shape as `runtime/test_main.c` in the C project -- one program that
## owns which of two things is running -- except that there the front end is
## the ACTUAL decompiled one and here it is recreated. See umk3_menu.gd.
extends Node

const _Menu := preload("res://umk3/umk3_menu.gd")
const _Stage := preload("res://umk3/umk3_stage.gd")
const _Fight := preload("res://umk3/umk3_fight.gd")
const _Fighter := preload("res://umk3/umk3_fighter.gd")
const _Audio := preload("res://umk3/umk3_audio.gd")

## A stamp on screen, because "the fix is in" and "the fix is in the copy you
## are running" are different claims and only the second one matters. Bump it
## with every export.
const BUILD := "2026-09-11 10:10  side-on + audio"
const UMK3Paths := preload("res://umk3/umk3_paths.gd")
## preload, not class_name: a class_name is invisible until the editor has
## indexed the project, and that is exactly when a fresh checkout runs.
const UMK3StageList := preload("res://umk3/umk3_stagelist.gd")

var _menu: Control
var _stage
var _fight
var _audio
var _cam: Camera3D
var _hud: Label
var _world: Node3D

## Two ways to look at the same stage: the fight, and the free camera that was
## here before it. V switches. The viewer is still the thing to reach for when
## a stage looks wrong -- it can orbit and step the scene's frames, which a
## fight camera deliberately cannot.
var _fight_mode := true

var _yaw := 0.0
var _pitch := -0.12
var _dist := 1.0
var _focus := Vector3.ZERO
var _shot := ""
var _shot_at := 0
## How many frames to run before the screenshot. The default is enough to get
## past loading; a longer one is how a frame rate gets measured with the game
## actually running, which is not what frame 20 shows.
var _shot_at_want := 20
var _index := 0
var _frame := 0
var _in_stage := false
var _drive := -1
var _pose := -1


func _ready() -> void:
	var res := UMK3Paths.resolve("")
	if res == "":
		var l := Label.new()
		# The example path uses FORWARD slashes on purpose. A Windows path in a
		# GDScript literal needs every backslash doubled, and one missed pair
		# turns \U into a unicode escape and the file stops parsing -- which is
		# exactly what happened while writing this message.
		l.text = "No game data found.\n\n" \
			+ "This build ships NONE of it. Run it once with the path to\n" \
			+ "your own extracted UMK3.app/res, quoted:\n\n" \
			+ "    UMK3.exe -- \"D:/games/UMK3.app/res\"\n\n" \
			+ "Forward slashes work. It is remembered after that."
		l.position = Vector2(40, 40)
		l.add_theme_font_size_override("font_size", 20)
		add_child(l)
		return

	_world = Node3D.new()
	add_child(_world)

	_menu = _Menu.new()
	_menu.play_stage.connect(_enter_stage)
	add_child(_menu)

	# **Every flag is read BEFORE anything acts on one.** `--stage` enters the
	# stage straight away, and when the parse ran in file order that happened
	# before `--drive` had been seen -- so the scripted input was installed one
	# frame after the fighter it was meant to drive, and the fighter just stood
	# there looking like a broken state machine.
	var args := OS.get_cmdline_user_args()
	var want_stage := -1
	var want_screen := -1
	for i in args.size():
		if i + 1 >= args.size():
			continue
		match args[i]:
			"--stage":  want_stage = int(args[i + 1])
			"--screen": want_screen = int(args[i + 1])
			"--drive":  _drive = int(args[i + 1])
			"--pose":   _pose = int(args[i + 1])
			"--yaw":    _Fighter.yaw_right = float(args[i + 1])
			"--wait":   _shot_at_want = int(args[i + 1])
			"--shot":
				_shot = args[i + 1]
				set_process(true)

	# `--stage N` goes straight in. It exists so the 3D path can be exercised
	# without clicking through the menu, which is how an empty view gets
	# diagnosed.
	if want_stage >= 0:
		await get_tree().process_frame
		_enter_stage(UMK3StageList.STAGES[
			wrapi(want_stage, 0, UMK3StageList.STAGES.size())])
	# `--screen N` shows a menu screen: 0 title, 1 main, 2 stage list. It exists
	# so the layout can be checked at any window size without clicking.
	if want_screen >= 0:
		await get_tree().process_frame
		_menu.show_screen(want_screen)


## `--shot <file>` writes what the window is showing and quits.
##
## Godot renders its own viewport to a file, which is the right way to look at
## this. An earlier attempt to check a build screen-scraped the desktop with
## GetWindowRect, SetForegroundWindow failed, and it captured the user's
## private windows instead. Never again: the program photographs itself.
func _process(_dt: float) -> void:
	if _in_stage and _hud and _fight_mode and _fight != null:
		_hud.text = _hud_text()
	if _shot == "":
		return
	if _shot_at == 0:
		_shot_at = _shot_at_want
	_shot_at -= 1
	if _shot_at > 0:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot)
	if _fight and _in_stage:
		for line in _fight.status().strip_edges().split("
"):
			print("[umk3] " + line)
	print("[umk3] wrote " + _shot)
	get_tree().quit()


func _enter_stage(stem: String) -> void:
	_index = UMK3StageList.STAGES.find(stem)
	if _index < 0:
		_index = 0
	_frame = 0
	_menu.visible = false
	_in_stage = true
	# Which button opened the stage list decides what the stage is for.
	if _menu.viewer_mode:
		_fight_mode = false

	if _cam == null:
		_cam = Camera3D.new()
		_cam.far = 60000.0          # raised per stage below; the moon is far
		_cam.near = 1.0
		_cam.fov = 25.0             # GAME_FOV_DEGREES, from the C port
		_world.add_child(_cam)
		_hud = Label.new()
		_hud.position = Vector2(12, 8)
		_hud.add_theme_font_size_override("font_size", 16)
		_hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		_hud.add_theme_constant_override("shadow_offset_y", 2)
		add_child(_hud)
	_cam.current = true
	_hud.visible = true
	_load_stage()
	# THIS is what reach is for: everything has to fit inside the frustum.
	_cam.far = maxf(_stage.reach * 2.5, 1000.0)
	_ensure_fight()


## Scorpion, once. The skin is 1,278 vertices and 2,503 triangles and the
## `.skinanim` is 344 frames; loading it per stage would be wasted work, so the
## fight survives a stage change and only the stage under it is rebuilt.
func _ensure_fight() -> void:
	if _fight != null:
		_fight.enabled = _fight_mode
		_fight.visible = _fight_mode
		return
	if _audio == null:
		_audio = _Audio.new(_menu.res_dir)
		add_child(_audio)
	_fight = _Fight.new()
	_fight.audio = _audio
	_world.add_child(_fight)
	if not _fight.setup(_menu.res_dir, _menu.textures, _cam):
		push_error("no fighter: " + str(_fight.error))
		print("[umk3] no fighter: " + str(_fight.error))
		_fight.queue_free()
		_fight = null
		_fight_mode = false
		return
	_fight.enabled = _fight_mode
	_fight.visible = _fight_mode
	if _drive >= 0:
		_fight.forced[0] = _drive
	# `--pose N` freezes both fighters on one animation frame. The frame list
	# names all 344 of Scorpion's, so this is how a clip range is checked
	# against what it actually draws instead of against its name.
	if _pose >= 0:
		_fight.enabled = false
		_fight.frozen = true
		for f in _fight.fighters:
			f.node.set_pose(_pose, _pose, 0.0)
	print("[umk3] fighter ready: %.1f tall, %.1f wide, %.1f deep, %.4f units per engine unit"
		% [_fight.height, _fight.width, _fight.depth, _fight.scale_units])


func _load_stage() -> void:
	if _stage:
		_stage.queue_free()
	_stage = _Stage.new()
	_world.add_child(_stage)
	var stem: String = UMK3StageList.STAGES[_index]
	if not _stage.build(_menu.res_dir, stem, _frame):
		_hud.text = "FAILED: " + _stage.error
		return
	var aabb := _world_aabb()
	var play := _play_aabb()

	# **`reach` is for the FAR PLANE, not for the framing**, and the union of
	# everything is not the stage either. Graveyard's sky dome is 41,921 units
	# across and its moon sits 28,600 out; framing off those puts the camera so
	# far back that the graveyard is a smudge -- which is exactly what the first
	# two attempts did.
	#
	# The C port frames off the FIGHTER and lets the stage be whatever size it
	# is. There is no fighter here, so `_play_aabb` stands in for one: it drops
	# the meshes that are far larger than typical, which is what the sky and the
	# moon are.
	var span := maxf(play.size.x, play.size.y)
	_focus = play.position + play.size * 0.5
	_focus.z = 0.0
	_dist = maxf(span * 1.1, 10.0)
	print("[umk3] all %s  play %s" % [aabb.size, play.size])
	print("[umk3] focus %s  dist %.0f  far %.0f  meshes %d"
		% [_focus, _dist, _cam.far, _stage.get_child_count()])
	_hud.text = _hud_text()
	if _audio and _fight_mode:
		_audio.music(UMK3StageList.MUSIC[_index])
	_update_cam()


func _hud_text() -> String:
	var stem: String = UMK3StageList.STAGES[_index]
	var head := "%d/%d  %s   frame %d   build %s\n" % [
		_index + 1, UMK3StageList.STAGES.size(),
		UMK3StageList.pretty(stem), _frame, BUILD]
	if _fight_mode and _fight != null:
		return head \
			+ "WASD move/jump/duck   U I O J K L  hi/lo punch, block, hi/lo kick, run\n" \
			+ "[ ] stage   V viewer   F5 reset   ESC menu\n" \
			+ _fight.status()
	return head + "[ ] stage   SPACE frame   V fight   ESC menu"


func _update_cam() -> void:
	if _cam == null:
		return
	# In fight mode the camera belongs to the fight: it frames the two
	# fighters, and an orbit written over it would be undone next frame.
	if _fight_mode and _fight != null:
		return
	var b := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	_cam.transform = Transform3D(b, _focus + b * Vector3(0, 0, _dist))


func _leave_stage() -> void:
	_in_stage = false
	if _fight:
		# Kept, not freed: the menu is in front of it and coming back should not
		# reload a character that takes a second to skin.
		_fight.enabled = false
		_fight.visible = false
	if _stage:
		_stage.queue_free()
		_stage = null
	if _hud:
		_hud.visible = false
	if _cam:
		_cam.current = false
	_menu.visible = true


func _unhandled_input(e: InputEvent) -> void:
	if not _in_stage:
		return
	if e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_yaw -= e.relative.x * 0.006
		_pitch = clampf(_pitch - e.relative.y * 0.006, -1.4, 1.4)
		_update_cam()
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(_dist * 0.9, 1.0); _update_cam()
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(_dist * 1.1, 200000.0); _update_cam()
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_ESCAPE:       _leave_stage()
			KEY_V:
				_fight_mode = not _fight_mode
				_ensure_fight()
				if not _fight_mode:
					_update_cam()
				_hud.text = _hud_text()
			KEY_F5:
				if _fight:
					_fight.reset()
			KEY_BRACKETLEFT:  _index = wrapi(_index - 1, 0, UMK3StageList.STAGES.size()); _frame = 0; _load_stage()
			KEY_BRACKETRIGHT: _index = wrapi(_index + 1, 0, UMK3StageList.STAGES.size()); _frame = 0; _load_stage()
			KEY_SPACE:
				if _stage and _stage.scene_graph.num_frames > 0:
					_frame = (_frame + 1) % _stage.scene_graph.num_frames
					_load_stage()


## The union of every placed mesh, for diagnosing an empty view.
func _world_aabb() -> AABB:
	var out := AABB()
	var first := true
	for c in _stage.get_children():
		if c is MeshInstance3D:
			var a: AABB = c.transform * c.get_aabb()
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
	return out


## The part of the stage a fight happens in.
##
## A stage's union includes its sky dome and its moon, which are an order of
## magnitude bigger than anything a camera should frame on. This keeps the
## meshes whose world size is within a few times the MEDIAN and drops the rest,
## so the backdrop still draws but no longer decides where the camera goes.
##
## The median rather than the mean: one 41,921-unit dome drags a mean far
## enough to keep itself.
func _play_aabb() -> AABB:
	var boxes: Array[AABB] = []
	var sizes: Array[float] = []
	for c in _stage.get_children():
		if c is MeshInstance3D:
			var a: AABB = c.transform * c.get_aabb()
			boxes.append(a)
			sizes.append(maxf(a.size.x, maxf(a.size.y, a.size.z)))
	if boxes.is_empty():
		return AABB()

	var sorted := sizes.duplicate()
	sorted.sort()
	var median: float = sorted[sorted.size() / 2]
	var limit := maxf(median * 6.0, 1.0)

	var out := AABB()
	var first := true
	for i in boxes.size():
		if sizes[i] > limit:
			continue
		if first:
			out = boxes[i]
			first = false
		else:
			out = out.merge(boxes[i])
	return out if not first else _world_aabb()
