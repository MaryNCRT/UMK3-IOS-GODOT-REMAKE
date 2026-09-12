## The pause menu. **A placeholder, and it says so on the screen.**
##
## What it is for right now is the two things the fight cannot do without a
## menu: choosing a device and rebinding it. The ten bits are the engine's and
## cannot move; which key or button produces each is ours, and this is where a
## player changes it.
##
## ## Both players on one screen
##
## The controls page is laid out the way a fighting game's key config has been
## laid out since the arcades: **player one down the left, player two down the
## right, side by side**, so there is no hidden second page and nothing to
## discover. The cursor moves between the columns with left and right.
##
## ## Three ways to work it, and all three do the same thing
##
## Mouse: click a cell to rebind it, click the device row to cycle it.
## Keyboard: arrows or WASD to move, Enter to rebind, R for defaults.
## Pad: d-pad to move, the bottom face button to pick, the right one to go
## back. A menu that can only be OPENED with a pad and then only be worked with
## a keyboard is worse than no menu.
##
## ## How rebinding works
##
## Pick a cell, press a key or a pad button, and it is taken. The next input
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
## The top row of each column is the device. A pad can only belong to one of
## them -- see umk3_input.gd's `detect` -- while the keyboard is always live
## for both, so two people can start playing without unplugging anything. The
## glyphs follow whatever each player ends up holding: a DualSense shows
## crosses and circles, an Xbox pad shows A and B, a Pro Controller shows
## Nintendo's own swapped pair.
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
## Which column the cursor is in on the controls page.
var cfg_player := 0
## Which bit is waiting for a key, or -1. The device row is not a bit.
var capturing := -1
## Capture into the pad column rather than the keyboard one.
var capture_pad := false
## True while the video page is up over this one. Both are Controls listening
## on `_input`, and the order they are called in is not something to lean on:
## the page in front says so explicitly.
var suspended := false

const ROOT_ITEMS := ["RESUME", "CONTROLS", "VIDEO OPTIONS", "RESTART ROUND",
	"QUIT TO MENU"]

## Row 0 of a column is the device and row 1 the glyph style; the ten bits
## follow. The style row is drawn for both players whether or not they have a
## pad -- a row that appears and disappears makes the two columns different
## heights and the cursor jump -- but it only ANSWERS to a player who has one.
const ROW_DEVICE := 0
const ROW_STYLE := 1
const BITS_FROM := 2
const ROWS := _Input.N + 2

## What the mouse can land on, rebuilt every time the page is drawn. Immediate
## mode: the rectangles a click is tested against are the ones just painted, so
## they cannot drift from what is on the screen.
var _hit: Array = []


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
		# A click somewhere else means "not that one after all" -- and then it
		# falls through, so the click still lands where it was aimed.
		if event is InputEventMouseButton and event.pressed:
			capturing = -1
		else:
			return

	if event is InputEventMouseMotion:
		queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_click(get_local_mouse_position())
		get_viewport().set_input_as_handled()
		queue_redraw()
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
			"left", "right":
				# Left and right walk between the two columns, which is what
				# they can only mean on a page with both players side by side.
				cfg_player = 1 - cfg_player
			"tab":   capture_pad = not capture_pad
			"ok":
				if sel == ROW_DEVICE:
					_cycle_device(1)
				elif sel == ROW_STYLE:
					input.cycle_style(cfg_player, 1)
				else:
					capturing = sel - BITS_FROM
			"reset":
				input.reset()
				input.save_cfg()
			"back":
				page = Page.ROOT
				sel = 1
				input.save_cfg()
	queue_redraw()


func _cycle_device(step: int) -> void:
	if input:
		input.cycle(cfg_player, step)


## A click, against whatever was last painted.
func _click(at: Vector2) -> void:
	for h in _hit:
		if not (h["rect"] as Rect2).has_point(at):
			continue
		match str(h["what"]):
			"root":
				sel = int(h["row"])
				_activate()
			"row":
				cfg_player = int(h["player"])
				sel = int(h["row"])
				if int(h["col"]) < 0:
					return
				capture_pad = int(h["col"]) == 1
				capturing = sel - BITS_FROM
			"device-":
				cfg_player = int(h["player"])
				sel = ROW_DEVICE
				_cycle_device(-1)
			"device+":
				cfg_player = int(h["player"])
				sel = ROW_DEVICE
				_cycle_device(1)
			"style-":
				cfg_player = int(h["player"])
				sel = ROW_STYLE
				input.cycle_style(cfg_player, -1)
			"style+":
				cfg_player = int(h["player"])
				sel = ROW_STYLE
				input.cycle_style(cfg_player, 1)
			"defaults":
				input.reset()
				input.save_cfg()
			"back":
				page = Page.ROOT
				sel = 1
				input.save_cfg()
		return


func _from_key(k: int) -> String:
	match k:
		KEY_UP, KEY_W:      return "up"
		KEY_DOWN, KEY_S:    return "down"
		KEY_LEFT, KEY_A:    return "left"
		KEY_RIGHT, KEY_D:   return "right"
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
	_hit.clear()
	if page == Page.ROOT:
		_draw_root(vp, font)
	else:
		_draw_controls(vp, font)


func _draw_root(vp: Vector2, font: Font) -> void:
	var mouse := get_local_mouse_position()
	var x := vp.x * 0.5
	var y := vp.y * 0.30
	_title(font, Vector2(x, y), "PAUSED")
	y += 26.0
	draw_string(font, Vector2(x - 118, y), "placeholder menu",
		HORIZONTAL_ALIGNMENT_LEFT, 236, 13, Color(0.6, 0.6, 0.65))
	y += 44.0
	for i in ROOT_ITEMS.size():
		var r := Rect2(x - 130, y - 17, 260, 24)
		_hit.append({"rect": r, "what": "root", "row": i, "player": 0,
			"col": -1})
		var on: bool = i == sel or r.has_point(mouse)
		if on:
			draw_rect(r, Color(0.9, 0.75, 0.15, 0.22), true)
		draw_string(font, Vector2(x - 118, y), ROOT_ITEMS[i],
			HORIZONTAL_ALIGNMENT_LEFT, 236, 17,
			Color(1, 0.88, 0.3) if on else Color(0.82, 0.82, 0.85))
		y += 30.0
	y += 16.0
	draw_string(font, Vector2(x - 130, y),
		"click, or W/S and ENTER, or the d-pad and A",
		HORIZONTAL_ALIGNMENT_LEFT, 420, 12, Color(0.5, 0.5, 0.55))


## Both players, side by side, the way a key config has always looked.
const COL_W := 330.0
const ROW_H := 24.0
const LABEL_W := 116.0
const CELL_W := 96.0


func _draw_controls(vp: Vector2, font: Font) -> void:
	var mouse := get_local_mouse_position()
	var w := COL_W * 2.0 + 56.0
	var h := ROW_H * float(ROWS) + 168.0
	var px := maxf(8.0, (vp.x - w) * 0.5)
	var py := maxf(8.0, (vp.y - h) * 0.42)
	# Opaque: the debug read-out is a Label behind this and a panel you can
	# read the frame counter through is not a panel.
	draw_rect(Rect2(px, py, w, h), Color(0.04, 0.04, 0.06, 1.0), true)
	draw_rect(Rect2(px, py, w, h), Color(1, 0.85, 0.2, 0.35), false, 1.0)

	_title(font, Vector2(px + w * 0.5, py + 34.0), "KEY CONFIG")
	var top := py + 52.0

	for p in 2:
		var cx := px + 28.0 + float(p) * COL_W
		var head := "PLAYER %d" % (p + 1)
		var hw := font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(font, Vector2(cx + (COL_W - 28.0 - hw) * 0.5, top + 16.0),
			head, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			Color(0.55, 0.8, 1.0) if p == 0 else Color(1.0, 0.55, 0.55))
		draw_string(font, Vector2(cx + LABEL_W, top + 32.0), "KEY",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.5, 0.55))
		draw_string(font, Vector2(cx + LABEL_W + CELL_W, top + 32.0), "PAD",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.5, 0.55))

		# The PICTURES fall back to Xbox when nothing is plugged in; what he is
		# actually holding is the separate line in the device row.
		var kind: String = input.pad_glyphs(p) if input else "xbox"
		var y := top + 38.0
		for row in ROWS:
			var here: bool = p == cfg_player and row == sel
			var full := Rect2(cx - 6.0, y, LABEL_W + CELL_W * 2.0 - 4.0, ROW_H)
			if here or full.has_point(mouse):
				draw_rect(full, Color(0.9, 0.75, 0.15,
					0.2 if here else 0.09), true)
			_hit.append({"rect": Rect2(full.position, Vector2(LABEL_W, ROW_H)),
				"what": "row", "row": row, "player": p, "col": -1})

			if row == ROW_DEVICE:
				draw_string(font, Vector2(cx, y + 17.0), "Device",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
					Color(1, 0.9, 0.4) if here else Color(0.8, 0.8, 0.84))
				_device_cell(font, Vector2(cx + LABEL_W, y), p, kind, mouse)
				y += ROW_H
				continue

			if row == ROW_STYLE:
				var got_pad: bool = input and input.has_pad(p)
				var lab := Color(0.8, 0.8, 0.84)
				if not got_pad:
					lab = Color(0.4, 0.4, 0.44)
				elif here:
					lab = Color(1, 0.9, 0.4)
				draw_string(font, Vector2(cx, y + 17.0), "Buttons",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, lab)
				_style_cell(font, Vector2(cx + LABEL_W, y), p, got_pad, mouse)
				y += ROW_H
				continue

			var i := row - BITS_FROM
			draw_string(font, Vector2(cx, y + 17.0), _Input.LABEL[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
				Color(1, 0.9, 0.4) if here else Color(0.85, 0.85, 0.88))
			for col in 2:
				var cell := Rect2(cx + LABEL_W + float(col) * CELL_W, y,
					CELL_W - 6.0, ROW_H)
				_hit.append({"rect": cell, "what": "row", "row": row,
					"player": p, "col": col})
				var on_col: bool = capture_pad == (col == 1)
				var waiting: bool = here and capturing == i and on_col
				var tex: Texture2D = null
				var text := ""
				if col == 0:
					tex = glyphs.key(int(input.keys[p][i]))
					text = _Glyphs.key_name(int(input.keys[p][i]))
				else:
					tex = glyphs.button(kind, int(input.pad[p][i]))
					text = _Glyphs.button_name(int(input.pad[p][i]))
				_slot(font, cell, tex, text, waiting,
					(here and on_col) or cell.has_point(mouse))
			y += ROW_H

	# The two actions, as things you can click, like the reference has them.
	var by := py + h - 54.0
	var dr := Rect2(px + 28.0, by, 150.0, 24.0)
	var xr := Rect2(px + 28.0 + COL_W, by, 150.0, 24.0)
	_hit.append({"rect": dr, "what": "defaults", "row": 0, "player": 0,
		"col": -1})
	_hit.append({"rect": xr, "what": "back", "row": 0, "player": 0, "col": -1})
	for pair in [[dr, "Defaults   (R)"], [xr, "Exit   (ESC)"]]:
		var r: Rect2 = pair[0]
		var hot := r.has_point(mouse)
		if hot:
			draw_rect(r, Color(0.9, 0.75, 0.15, 0.12), true)
		draw_string(font, Vector2(r.position.x, r.position.y + 17.0),
			str(pair[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(1, 0.9, 0.4) if hot else Color(0.7, 0.7, 0.75))

	draw_string(font, Vector2(px + 28.0, py + h - 16.0),
		"click a cell to rebind it   TAB %s   left/right swaps player   ESC back"
		% ("pad column" if capture_pad else "key column"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.45, 0.5))


## The device cell: **two arrows you can click and the name between them**,
## then what he is actually holding.
##
## The arrows are there because left and right on this page mean the other
## PLAYER -- with both columns on screen they cannot mean anything else -- so
## the one row that has a value to step needs somewhere to click. Enter and the
## pad's bottom face button step it forward too.
func _device_cell(font: Font, at: Vector2, p: int, kind: String,
		mouse: Vector2) -> void:
	var lw := 16.0
	var w := CELL_W * 2.0 - 6.0
	var left := Rect2(at.x, at.y, lw, ROW_H)
	var right := Rect2(at.x + w - lw, at.y, lw, ROW_H)
	var mid := Rect2(at.x + lw, at.y, w - lw * 2.0, ROW_H)
	_hit.append({"rect": left, "what": "device-", "row": ROW_DEVICE,
		"player": p, "col": 0})
	_hit.append({"rect": right, "what": "device+", "row": ROW_DEVICE,
		"player": p, "col": 0})
	_hit.append({"rect": mid, "what": "device+", "row": ROW_DEVICE,
		"player": p, "col": 0})

	for pair in [[left, "<"], [right, ">"]]:
		var r: Rect2 = pair[0]
		var hot := r.has_point(mouse)
		if hot:
			draw_rect(r, Color(1, 0.9, 0.4, 0.18), true)
		draw_string(font, Vector2(r.position.x + 5.0, r.position.y + 17.0),
			str(pair[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(1, 0.95, 0.6) if hot else Color(0.8, 0.8, 0.5))

	var pick: String = input.choice_name(str(input.pref[p])) if input else "?"
	if pick.length() > 20:
		pick = pick.substr(0, 19) + "…"
	draw_string(font, Vector2(mid.position.x + 4.0, at.y + 17.0), pick,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.85, 1.0))

	# No second column saying what he GOT. Without an automatic option the
	# choice IS what he gets, and the one case where it is not -- a named pad
	# that is unplugged -- the value itself says so. The old extra column ran
	# into player two's labels.


## The glyph-style cell. Two arrows and the name between them, greyed out for
## a player with no pad -- there is nothing to override on a keyboard.
func _style_cell(font: Font, at: Vector2, p: int, got_pad: bool,
		mouse: Vector2) -> void:
	var lw := 16.0
	var w := CELL_W * 2.0 - 6.0
	if got_pad:
		var left := Rect2(at.x, at.y, lw, ROW_H)
		var right := Rect2(at.x + w - lw, at.y, lw, ROW_H)
		var mid := Rect2(at.x + lw, at.y, w - lw * 2.0, ROW_H)
		_hit.append({"rect": left, "what": "style-", "row": ROW_STYLE,
			"player": p, "col": 0})
		_hit.append({"rect": right, "what": "style+", "row": ROW_STYLE,
			"player": p, "col": 0})
		_hit.append({"rect": mid, "what": "style+", "row": ROW_STYLE,
			"player": p, "col": 0})
		for pair in [[left, "<"], [right, ">"]]:
			var r: Rect2 = pair[0]
			var hot := r.has_point(mouse)
			if hot:
				draw_rect(r, Color(1, 0.9, 0.4, 0.18), true)
			draw_string(font, Vector2(r.position.x + 5.0, r.position.y + 17.0),
				str(pair[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(1, 0.95, 0.6) if hot else Color(0.8, 0.8, 0.5))
		draw_string(font, Vector2(at.x + lw + 4.0, at.y + 17.0),
			input.style_name(p), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.6, 0.85, 1.0))
		return
	draw_string(font, Vector2(at.x + lw + 4.0, at.y + 17.0), "needs a pad",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.4, 0.44))


## One binding cell: the picture when there is one, the name when there is not,
## and "press..." while it is waiting.
func _slot(font: Font, cell: Rect2, tex: Texture2D, text: String,
		waiting: bool, focus: bool) -> void:
	if focus:
		draw_rect(cell, Color(1, 0.9, 0.4, 0.12), true)
		draw_rect(cell, Color(1, 0.9, 0.4, 0.45), false, 1.0)
	if waiting:
		draw_string(font, Vector2(cell.position.x + 6.0,
			cell.position.y + 17.0), "press...", HORIZONTAL_ALIGNMENT_LEFT,
			-1, 13, Color(0.4, 1.0, 0.5))
		return
	if tex:
		draw_texture_rect(tex, Rect2(cell.position.x + 6.0,
			cell.position.y + 2.0, 20.0, 20.0), false)
		return
	draw_string(font, Vector2(cell.position.x + 6.0, cell.position.y + 17.0),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.9, 0.95))


func _title(font: Font, centre: Vector2, text: String) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	draw_string_outline(font, Vector2(centre.x - w * 0.5, centre.y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 4, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(centre.x - w * 0.5, centre.y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.88, 0.3))
