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
const _Effects := preload("res://umk3/umk3_effects.gd")
const _InputHud := preload("res://umk3/umk3_inputhud.gd")
const _Bars := preload("res://umk3/umk3_hud.gd")
const _Pause := preload("res://umk3/umk3_pause.gd")
const _InputCfg := preload("res://umk3/umk3_input.gd")
const _Video := preload("res://umk3/umk3_video.gd")
const _Options := preload("res://umk3/umk3_options.gd")

## A stamp on screen, because "the fix is in" and "the fix is in the copy you
## are running" are different claims and only the second one matters. Bump it
## with every export.
const BUILD := "2026-09-12 10:00  key config, monitors, real pause"
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
var _keys: Control
var _bars: Control
var _pause: Control
## The video settings and the page that edits them. **One of each**, shared by
## the front end and the pause menu, so a change made in one is already true in
## the other.
var _video = null
var _options: Control
## `--menu 1` opens the pause menu on the first frame, which is how it is
## photographed without a hand on the keyboard.
var _open_menu := 0
## The pad's Start button, last frame, so a held button pauses once.
var _start_held := false
## The bindings, shared by the fight, the panel and the pause menu --
## **one object, so a rebind cannot reach one of them and miss another.**
var _input = null
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
## The same for player two. Two of them is what lets a hit be tested against a
## block without a second pair of hands.
var _drive2 := -1
## `--seq 4,0,4,0,32` plays one input word per tick, for testing a notation.
var _seq := ""
var _pose := -1
## `--stagelight 0` turns the stage lighting OFF. On is the default; see
## umk3_stage.gd for why this is a choice between two approximations rather
## than a setting with a right answer.
var _stage_light := true
## H toggles the hitboxes; `--hitbox 1` starts with them on.
var _hitbox := false
## `--gap N` sets the half-gap a round opens with, for testing reach and hits.
var _gap := -1
## `--wins N` puts N rounds on both players' counters, for looking at the HUD.
var _wins := -1


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

	# Which copy of the data this run is using. Worth printing: a build that
	# carries its own and a build reading someone's install look identical
	# until something is missing from one of them.
	print("[umk3] data: " + res)

	_world = Node3D.new()
	# **PAUSABLE, explicitly, and this is the whole of why the fight kept
	# moving behind the pause menu.** This node is set PROCESS_MODE_ALWAYS so
	# that it can still poll the pad's Start button while the tree is paused --
	# and ALWAYS propagates DOWN through every child left on INHERIT, which the
	# world and the fight inside it were. Saying it here stops the inheritance
	# at the one node that must not keep running.
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_world)

	# The window is put where it was left BEFORE anything is drawn into it.
	_video = _Video.new()
	_video.apply()
	# Written on the first run too, so the file exists before anything is
	# changed and a player can see where the settings live.
	_video.save_cfg()

	_menu = _Menu.new()
	_menu.play_stage.connect(_enter_stage)
	_menu.open_options.connect(_show_options)
	add_child(_menu)

	# On top of everything, including the pause menu, and running while the
	# tree is paused -- it is shown from inside the pause.
	_options = _Options.new()
	_options.video = _video
	_options.process_mode = Node.PROCESS_MODE_ALWAYS
	_options.closed.connect(func() -> void:
		if _pause:
			_pause.suspended = false)
	add_child(_options)

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
			"--drive2": _drive2 = int(args[i + 1])
			"--seq":    _seq = args[i + 1]
			"--pose":   _pose = int(args[i + 1])
			"--yaw":    _Fighter.yaw_right = float(args[i + 1])
			"--wait":   _shot_at_want = int(args[i + 1])
			"--stagelight": _stage_light = int(args[i + 1]) != 0
			"--fog":    _Effects.opacity = float(args[i + 1])
			"--hitbox": _hitbox = int(args[i + 1]) != 0
			"--gap":    _gap = int(args[i + 1])
			"--wins":   _wins = int(args[i + 1])
			"--menu":   _open_menu = int(args[i + 1])
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
	# **Pads are re-checked every frame**, so one can be picked up mid-round
	# and the panel and the menu follow it without being told.
	if _input:
		_input.detect()
		_pad_start()
	if _open_menu > 0 and _pause and _in_stage:
		var which := _open_menu
		_open_menu = 0
		_pause.open()
		if which == 2:
			_pause.page = 1               # straight to the controls page
		elif which == 3:
			_show_options()               # straight to the video page
	var want_pause := false
	if _pause != null and _pause.visible:
		want_pause = true
	if _options != null and _options.visible and _in_stage:
		want_pause = true
	if want_pause:
		get_tree().paused = true
	elif get_tree().paused:
		get_tree().paused = false
	if _in_stage and _hud and _fight_mode and _fight != null:
		_hud.text = _hud_text()
		if _keys:
			_keys.visible = true
			_keys.set_state(_fight.last_raw, _fight.last_special)
		if _bars:
			_bars.visible = true
	elif _keys:
		_keys.visible = false
		if _bars:
			_bars.visible = false
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


## **Start pauses.** Either player's pad, edge detected, and it goes through
## the same toggle Escape does -- so a pad can open the menu, work it and close
## it without ever touching the keyboard.
##
## Polled rather than taken as an event because the tree is PAUSED while the
## menu is up, and this node is one of the two that keeps running.
func _pad_start() -> void:
	var down := false
	for p in 2:
		var d: int = int(_input.device[p])
		if d >= 0 and Input.is_joy_button_pressed(d, JOY_BUTTON_START):
			down = true
	if down and not _start_held:
		_toggle_pause()
	_start_held = down


## The one video page, from wherever it was asked for.
func _show_options() -> void:
	if _options == null:
		return
	if _pause:
		_pause.suspended = true
	_options.open()


func _toggle_pause() -> void:
	if _pause == null or not _in_stage or not _fight_mode:
		return
	if _pause.visible:
		_pause.close()
	else:
		_pause.open()


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
		# **The debug read-out lives at the BOTTOM.** The health bars are the
		# top of the screen now and two things cannot share it.
		_hud = Label.new()
		_hud.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_hud.grow_vertical = Control.GROW_DIRECTION_BEGIN
		# Small, and hard against the bottom edge. It is a read-out, not part
		# of the game's own screen, and it should look like one.
		_hud.position = Vector2(10, -92)
		_hud.add_theme_font_size_override("font_size", 12)
		_hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		_hud.add_theme_constant_override("shadow_offset_y", 2)
		add_child(_hud)
		# The input panel, down the right-hand side. It shows the ENGINE's ten
		# bits, so an input that does not light here never reached the fight.
		_keys = _InputHud.new()
		_keys.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_keys)
		# The health bars, drawn out of the game's own HUD_TPAGE sprites.
		# Under the input panel in the tree so the panel stays readable.
		_bars = _Bars.new()
		add_child(_bars)
		# The pause menu, on top of everything, and the bindings it edits.
		_input = _InputCfg.new()
		_keys.input = _input
		_pause = _Pause.new()
		_pause.input = _input
		_pause.visible = false
		# **The menu and this node keep running while the tree is paused**,
		# or the thing that unpauses would itself be asleep.
		_pause.process_mode = Node.PROCESS_MODE_ALWAYS
		process_mode = Node.PROCESS_MODE_ALWAYS
		_pause.reset_round.connect(func() -> void:
			if _fight:
				_fight.reset())
		_pause.quit_match.connect(_leave_stage)
		_pause.open_video.connect(_show_options)
		add_child(_pause)
		# The pause menu goes UNDER the options page, which was added first.
		move_child(_options, -1)
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
	_fight.input = _input
	if _bars:
		_bars.setup(_menu.textures)
		_fight.hud = _bars
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
	if _drive2 >= 0:
		_fight.forced[1] = _drive2
	if _seq != "":
		for s in _seq.split(","):
			_fight.forced_seq.append(int(s))
	_fight.show_hitbox = _hitbox
	if _wins >= 0:
		for f in _fight.fighters:
			f.wins = _wins
	if _gap >= 0:
		_fight.start_gap = _gap
		_fight.reset()
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
	_stage.use_lighting = _stage_light
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
			+ (("[ ] stage  V viewer  F5 reset  F6/F7 fog %.2f  F8/F9 rate%+d"
				+ "  F10/F11 speed %.1fx  H box %s  ESC menu\n")
				% [_Effects.opacity, _fight.rate_bias, _fight.game_speed,
					"on" if _fight.show_hitbox else "off"]) \
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
		# **Escape opens the pause menu now** rather than dropping the stage;
		# quitting to the menu is an item inside it.
		if e.keycode == KEY_ESCAPE and _pause and _fight_mode:
			_toggle_pause()
			return
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
			# The hitboxes. A measured box and a chosen reach drawn side by
			# side, which is the point of showing them at all.
			KEY_H:
				if _fight:
					_fight.show_hitbox = not _fight.show_hitbox
					_hitbox = _fight.show_hitbox
			# The fog is a LOOK, and a look is dialled by eye rather than
			# argued one screenshot at a time. These move it live, and the
			# value is in the HUD so it can be reported back as a number.
			KEY_F6:
				_Effects.opacity = maxf(0.0, _Effects.opacity - 0.05)
			KEY_F7:
				_Effects.opacity = minf(1.0, _Effects.opacity + 0.05)
			# recovered. Same reason as the fog: a feel is dialled, not argued.
			# Lower is FASTER -- it is game frames held per animation frame.
			KEY_F8:
				if _fight:
					_fight.rate_bias -= 1
			KEY_F9:
				if _fight:
					_fight.rate_bias += 1
			# The whole game's speed. The engine ticks once per drawn frame and
			# the rate it drew at is not recovered yet, so this is the one
			# number here that is honestly still open.
			KEY_F10:
				if _fight:
					_fight.game_speed = maxf(0.25, _fight.game_speed - 0.1)
			KEY_F11:
				if _fight:
					_fight.game_speed = minf(3.0, _fight.game_speed + 0.1)
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
