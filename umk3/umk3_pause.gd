## The pause menu. **A placeholder, and it says so on the screen.**
##
## What it is for right now is the one thing the fight cannot do without a
## menu: rebinding. The ten bits are the engine's and cannot move; which key or
## button produces each is ours, and this is where a player changes it.
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
## ## Devices
##
## Player one takes the first pad that is plugged in and player two the second,
## re-checked every frame, so a pad can be picked up mid-match. The glyphs
## change with it: a DualSense shows crosses and circles, an Xbox pad shows
## A and B, a Pro Controller shows Nintendo's own swapped pair.
extends Control

const _Glyphs := preload("res://umk3/umk3_glyphs.gd")
const _Input := preload("res://umk3/umk3_input.gd")

signal closed
signal reset_round
signal quit_match

enum Page { ROOT, CONTROLS }

var input = null                         ## the UMK3Input the fight uses
var glyphs = null

var page := Page.ROOT
var sel := 0
var cfg_player := 0
## Which bit is waiting for a key, or -1.
var capturing := -1
## Capture into the pad column rather than the keyboard one.
var capture_pad := false

const ROOT_ITEMS := ["RESUME", "CONTROLS", "RESTART ROUND", "QUIT TO MENU"]


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
	if not visible:
		return

	# **A capture eats the next real press, whatever it is.**
	if capturing >= 0:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				capturing = -1
			elif not capture_pad:
				input.keys[cfg_player][capturing] = event.keycode
				capturing = -1
			get_viewport().set_input_as_handled()
			queue_redraw()
			return
		if event is InputEventJoypadButton and event.pressed and capture_pad:
			input.pad[cfg_player][capturing] = event.button_index
			capturing = -1
			get_viewport().set_input_as_handled()
			queue_redraw()
			return
		return

	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.keycode
	get_viewport().set_input_as_handled()

	if page == Page.ROOT:
		match k:
			KEY_UP, KEY_W:
				sel = posmod(sel - 1, ROOT_ITEMS.size())
			KEY_DOWN, KEY_S:
				sel = posmod(sel + 1, ROOT_ITEMS.size())
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_activate()
			KEY_ESCAPE:
				close()
	else:
		match k:
			KEY_UP, KEY_W:
				sel = posmod(sel - 1, _Input.N)
			KEY_DOWN, KEY_S:
				sel = posmod(sel + 1, _Input.N)
			KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D:
				cfg_player = 1 - cfg_player
			KEY_TAB:
				capture_pad = not capture_pad
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				capturing = sel
			KEY_R:
				input.reset()
			KEY_ESCAPE:
				page = Page.ROOT
				sel = 1
				input.save_cfg()
	queue_redraw()


func _activate() -> void:
	match sel:
		0:
			close()
		1:
			page = Page.CONTROLS
			sel = 0
		2:
			reset_round.emit()
			close()
		3:
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
	draw_string(font, Vector2(x - 130, y), "W/S move    ENTER pick    ESC back",
		HORIZONTAL_ALIGNMENT_LEFT, 300, 12, Color(0.5, 0.5, 0.55))


func _draw_controls(vp: Vector2, font: Font) -> void:
	var x := vp.x * 0.5 - 200.0
	var y := vp.y * 0.14
	# A panel of its own: the debug read-out lives at the bottom of the screen
	# and the rows would otherwise be read through it.
	draw_rect(Rect2(x - 22, y - 34, 444, 400), Color(0.04, 0.04, 0.06, 0.95),
		true)
	draw_rect(Rect2(x - 22, y - 34, 444, 400), Color(1, 0.85, 0.2, 0.35),
		false, 1.0)
	_title(font, Vector2(vp.x * 0.5, y), "CONTROLS")
	y += 34.0

	# Which player, and what he is holding.
	var kind: String = input.pad_kind(cfg_player) if input else "kb"
	var dev: int = input.device[cfg_player] if input else -1
	var who := "PLAYER %d" % (cfg_player + 1)
	var on_what := "keyboard only"
	if dev >= 0:
		# Pad names are whatever the driver says and can be a paragraph; the
		# kind is what a player actually needs to see.
		var nm := Input.get_joy_name(dev)
		if nm.length() > 22:
			nm = nm.substr(0, 21) + "…"
		on_what = "%s  (%s)" % [nm, kind.to_upper()]
	draw_string(font, Vector2(x, y), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
		Color(1, 0.88, 0.3))
	draw_string(font, Vector2(x + 110, y), on_what, HORIZONTAL_ALIGNMENT_LEFT,
		-1, 13, Color(0.6, 0.75, 0.9))
	y += 24.0
	draw_string(font, Vector2(x, y),
		"A/D swap player   TAB %s   ENTER rebind   R defaults   ESC back"
		% ("column: PAD" if capture_pad else "column: KEY"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.55))
	y += 22.0

	draw_string(font, Vector2(x + 150, y), "KEYBOARD", HORIZONTAL_ALIGNMENT_LEFT,
		-1, 12, Color(0.55, 0.55, 0.6))
	draw_string(font, Vector2(x + 280, y), "PAD", HORIZONTAL_ALIGNMENT_LEFT,
		-1, 12, Color(0.55, 0.55, 0.6))
	y += 10.0

	for i in _Input.N:
		var on := i == sel
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
