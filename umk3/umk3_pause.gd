## The pause menu. **A placeholder, and it says so on the screen.**
##
## What it is for right now is the one thing the fight cannot do without a
## menu: choosing a device and rebinding it. The ten bits are the engine's and
## cannot move; which key or button produces each is ours, and this is where a
## player changes it.
##
## ## How rebinding works
##
## Pick a row, press a key or a pad button, and it is taken. The next input
## event is captured raw -- no action map, no InputMap -- because the fight
## reads raw keys and raw buttons and a menu that bound anything else would be
## binding something the fight never looks at.
##
## Escape cancels a capture; Escape with nothing capturing closes the page.
##
## **Every change is written to disk the moment it is made**, not when the menu
## closes: a menu that saves on the way out loses everything if the window is
## shut with the mouse, which is exactly how somebody would try it.
##
## ## Devices
##
## The top row of the page is the device, and it is per player. A pad can only
## belong to one of them -- see umk3_input.gd's `detect` -- while the keyboard
## is always live for both, so two people can start playing without unplugging
## anything. The glyphs follow whatever each player ends up holding: a
## DualSense shows crosses and circles, an Xbox pad shows A and B, a Pro
## Controller shows Nintendo's own swapped pair.
##
## ## Driving it with a pad
##
## Start opens and closes it, the d-pad moves, the bottom face button picks and
## the right one goes back. A menu that can only be opened with a pad and then
## only be worked with a keyboard is worse than no menu.
extends Control

const _Glyphs := preload("res://umk3/umk3_glyphs.gd")
const _Input := preload("res://umk3/umk3_input.gd")

signal closed
signal reset_round
signal quit_match
## The pause menu does not own the video page -- the front end shows the same
## one -- so it asks for it rather than drawing it.
signal open_video

enum Page { ROOT, CONTROLS }

var input = null                         ## the UMK3Input the fight uses
var glyphs = null

var page := Page.ROOT
var sel := 0
var cfg_player := 0
## Which bit is waiting for a key, or -1. The device row is not a bit and
## cannot be captured into.
var capturing := -1
## Capture into the pad column rather than the keyboard one.
var capture_pad := false
## True while the video page is up over this one. Both are Controls listening
## on `_input`, and the order they are called in is not something to lean on:
## the page in front says so explicitly.
var suspended := false

const ROOT_ITEMS := ["RESUME", "CONTROLS", "VIDEO OPTIONS", "RESTART ROUND",
	"QUIT TO MENU"]

## Row 0 of the controls page is the device; the ten bits follow it.
const ROW_DEVICE := 0
const ROWS := _Input.N + 1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	glyphs = _Glyphs.new()
	set_process_input(true)


func open() -> void:
	visible = true
	page = Page.ROOT
	sel = 0
	capturing = -1
	queue_redraw()


func close() -> void:
	visible = false
	capturing = -1
	if input:
		input.save_cfg()
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible or suspended:
		return

	# **A capture eats the next real press, whatever it is.**
	if capturing >= 0:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				capturing = -1
			elif not capture_pad:
				input.keys[cfg_player][capturing] = event.keycode
				input.save_cfg()
				capturing = -1
			get_viewport().set_input_as_handled()
			queue_redraw()
			return
		if event is InputEventJoypadButton and event.pressed and capture_pad:
			input.pad[cfg_player][capturing] = event.button_index
			input.save_cfg()
			capturing = -1
			get_viewport().set_input_as_handled()
			queue_redraw()
			return
		# **A trigger is not a button.** On Windows an Xbox-compatible pad goes
		# through XInput, and XInput reports LT and RT as analogue axes: no
		# `InputEventJoypadButton` is ever sent for them. Without this, the two
		# buttons a fighting-game player most wants for block and run are the
		# two that cannot be bound.
		if event is InputEventJoypadMotion and capture_pad:
			if absf(event.axis_value) > _Input.AXIS_ON:
				var dir := 1 if event.axis_value > 0.0 else 0
				input.pad[cfg_player][capturing] = (_Input.AXIS
					+ int(event.axis) * 2 + dir)
				input.save_cfg()
				capturing = -1
				get_viewport().set_input_as_handled()
				queue_redraw()
			return
		return

	var act := ""
	if event is InputEventKey and event.pressed and not event.echo:
		act = _from_key(event.keycode)
	elif event is InputEventJoypadButton and event.pressed:
		act = _from_pad(event.button_index)
	if act == "":
		return
	get_viewport().set_input_as_handled()

	if page == Page.ROOT:
		match act:
			"up":    sel = posmod(sel - 1, ROOT_ITEMS.size())
			"down":  sel = posmod(sel + 1, ROOT_ITEMS.size())
			"ok":    _activate()
			"back":  close()
	else:
		match act:
			"up":    sel = posmod(sel - 1, ROWS)
			"down":  sel = posmod(sel + 1, ROWS)
			"left":  _sideways(-1)
			"right": _sideways(1)
			"swap":  _swap_player()
			"tab":   capture_pad = not capture_pad
			"ok":
				if sel == ROW_DEVICE:
					_sideways(1)
				else:
					capturing = sel - 1
			"reset":
				input.reset()
				input.save_cfg()
			"back":
				page = Page.ROOT
				sel = 1
				input.save_cfg()
	queue_redraw()


## Left and right mean the device on the device row and the player anywhere
## else, which is the only place on the page where a direction is ambiguous.
func _sideways(step: int) -> void:
	if sel == ROW_DEVICE:
		if input:
			input.cycle(cfg_player, step)
		return
	_swap_player()


func _swap_player() -> void:
	cfg_player = 1 - cfg_player
	capturing = -1


func _from_key(k: int) -> String:
	match k:
		KEY_UP, KEY_W:      return "up"
		KEY_DOWN, KEY_S:    return "down"
		KEY_LEFT:           return "left"
		KEY_RIGHT:          return "right"
		KEY_A, KEY_D:       return "swap"
		KEY_TAB:            return "tab"
		KEY_R:              return "reset"
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: return "ok"
		KEY_ESCAPE:         return "back"
	return ""


func _from_pad(b: int) -> String:
	match b:
		JOY_BUTTON_DPAD_UP:    return "up"
		JOY_BUTTON_DPAD_DOWN:  return "down"
		JOY_BUTTON_DPAD_LEFT:  return "left"
		JOY_BUTTON_DPAD_RIGHT: return "right"
		JOY_BUTTON_A:          return "ok"
		JOY_BUTTON_B:          return "back"
		JOY_BUTTON_X:          return "tab"
		JOY_BUTTON_Y:          return "reset"
	return ""


func _activate() -> void:
	match sel:
		0:
			close()
		1:
			page = Page.CONTROLS
			sel = 0
		2:
			# Shown OVER the pause menu, which stays up behind it, so closing
			# the video page comes back here rather than back to the fight.
			open_video.emit()
		3:
			reset_round.emit()
			close()
		4:
			quit_match.emit()
			close()


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


# -------------------------------------------------------------------- drawing
func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.72), true)
	var font := ThemeDB.fallback_font
	if page == Page.ROOT:
		_draw_root(vp, font)
	else:
		_draw_controls(vp, font)


func _draw_root(vp: Vector2, font: Font) -> void:
	var x := vp.x * 0.5
	var y := vp.y * 0.30
	_title(font, Vector2(x, y), "PAUSED")
	y += 26.0
	draw_string(font, Vector2(x - 118, y), "placeholder menu",
		HORIZONTAL_ALIGNMENT_LEFT, 236, 13, Color(0.6, 0.6, 0.65))
	y += 44.0
	for i in ROOT_ITEMS.size():
		var on := i == sel
		if on:
			draw_rect(Rect2(x - 130, y - 17, 260, 24),
				Color(0.9, 0.75, 0.15, 0.22), true)
		draw_string(font, Vector2(x - 118, y), ROOT_ITEMS[i],
			HORIZONTAL_ALIGNMENT_LEFT, 236, 17,
			Color(1, 0.88, 0.3) if on else Color(0.82, 0.82, 0.85))
		y += 30.0
	y += 16.0
	draw_string(font, Vector2(x - 130, y),
		"W/S or d-pad move    ENTER or A pick    ESC or START back",
		HORIZONTAL_ALIGNMENT_LEFT, 420, 12, Color(0.5, 0.5, 0.55))


func _draw_controls(vp: Vector2, font: Font) -> void:
	var w := 444.0
	var h := 26.0 * float(ROWS) + 130.0
	var x := maxf(12.0, vp.x * 0.5 - w * 0.5) + 22.0
	var y := maxf(34.0, (vp.y - h) * 0.45) + 34.0
	# A panel of its own: the debug read-out lives at the bottom of the screen
	# and the rows would otherwise be read through it.
	draw_rect(Rect2(x - 22, y - 34, w, h), Color(0.04, 0.04, 0.06, 0.95), true)
	draw_rect(Rect2(x - 22, y - 34, w, h), Color(1, 0.85, 0.2, 0.35), false, 1.0)
	_title(font, Vector2(x - 22 + w * 0.5, y), "CONTROLS")
	y += 34.0

	# Which player. Arrows on both sides because this is the control a player
	# is most likely to miss, and missing it is what "there is no player two"
	# looks like.
	var who := "< PLAYER %d >" % (cfg_player + 1)
	draw_string(font, Vector2(x, y), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
		Color(1, 0.88, 0.3))
	draw_string(font, Vector2(x + 140, y), "A/D or left/right swaps player",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.55, 0.6))
	y += 22.0
	draw_string(font, Vector2(x, y),
		"TAB %s   ENTER rebind   R defaults   ESC back"
		% ("column: PAD" if capture_pad else "column: KEY"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.55))
	y += 22.0

	draw_string(font, Vector2(x + 150, y), "KEYBOARD", HORIZONTAL_ALIGNMENT_LEFT,
		-1, 12, Color(0.55, 0.55, 0.6))
	draw_string(font, Vector2(x + 280, y), "PAD", HORIZONTAL_ALIGNMENT_LEFT,
		-1, 12, Color(0.55, 0.55, 0.6))
	y += 10.0

	var kind: String = input.pad_kind(cfg_player) if input else "kb"

	# The device row, first, because what a player is holding decides whether
	# the pad column below it means anything at all.
	var on_dev := sel == ROW_DEVICE
	if on_dev:
		draw_rect(Rect2(x - 8, y - 2, 416, 26), Color(0.9, 0.75, 0.15, 0.18),
			true)
	draw_string(font, Vector2(x, y + 17), "Device",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Color(1, 0.9, 0.4) if on_dev else Color(0.85, 0.85, 0.88))
	var pick: String = input.choice_name(str(input.pref[cfg_player])) if input else "?"
	if pick.length() > 26:
		pick = pick.substr(0, 25) + "…"
	# What he ASKED for, and then what he actually got -- they differ whenever
	# the other player already has that pad, or it is not plugged in.
	var got := "-- nothing"
	if input:
		var dev: int = input.device[cfg_player]
		got = "-> %s" % kind.to_upper() if dev >= 0 else "-> keyboard"
	draw_string(font, Vector2(x + 150, y + 17), "< %s >" % pick,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.85, 1.0))
	draw_string(font, Vector2(x + 340, y + 17), got,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.75, 0.55))
	y += 26.0

	for i in _Input.N:
		var on := i + 1 == sel
		if on:
			draw_rect(Rect2(x - 8, y - 2, 416, 26),
				Color(0.9, 0.75, 0.15, 0.18), true)
		draw_string(font, Vector2(x, y + 17), _Input.LABEL[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(1, 0.9, 0.4) if on else Color(0.85, 0.85, 0.88))

		var wait_key := capturing == i and not capture_pad
		var wait_pad := capturing == i and capture_pad
		_slot(font, Vector2(x + 150, y), glyphs.key(int(input.keys[cfg_player][i])),
			_Glyphs.key_name(int(input.keys[cfg_player][i])), wait_key,
			on and not capture_pad)
		_slot(font, Vector2(x + 280, y),
			glyphs.button(kind, int(input.pad[cfg_player][i])),
			_Glyphs.button_name(int(input.pad[cfg_player][i])), wait_pad,
			on and capture_pad)
		y += 26.0


## One binding cell: the picture when there is one, the name when there is not,
## and "press..." while it is waiting.
func _slot(font: Font, at: Vector2, tex: Texture2D, text: String,
		waiting: bool, focus: bool) -> void:
	if focus:
		draw_rect(Rect2(at.x - 4, at.y - 1, 112, 24),
			Color(1, 0.9, 0.4, 0.13), true)
		draw_rect(Rect2(at.x - 4, at.y - 1, 112, 24),
			Color(1, 0.9, 0.4, 0.5), false, 1.0)
	if waiting:
		draw_string(font, Vector2(at.x, at.y + 17), "press...",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.4, 1.0, 0.5))
		return
	if tex:
		draw_texture_rect(tex, Rect2(at.x, at.y, 22, 22), false)
		return
	draw_string(font, Vector2(at.x, at.y + 17), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.9, 0.95))


func _title(font: Font, centre: Vector2, text: String) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	draw_string_outline(font, Vector2(centre.x - w * 0.5, centre.y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 4, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(centre.x - w * 0.5, centre.y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.88, 0.3))
