## The video options page. **One Control, shown from both menus.**
##
## The pause menu opens it and so does the front end, and they open the SAME
## node with the same UMK3Video behind it -- so a change made in one is already
## true in the other, and there is no second copy of the list to fall out of
## step.
##
## Every row is a cycle: left and right step it, and the change lands
## immediately and is written to disk immediately. There is no apply button,
## because a setting that needs confirming is a setting you cannot see the
## effect of while you choose it.
##
## Keyboard and pad both drive it, the same way the pause menu does.
extends Control

const _Video := preload("res://umk3/umk3_video.gd")

signal closed

var video = null                         ## the UMK3Video everything shares
var sel := 0

enum Row { SIZE, MODE, AA, VSYNC, FPS, BACK }
const ROW_NAME := ["Resolution", "Window", "Antialiasing", "Vertical sync",
	"Frame limit", "Back"]
const N := 6


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process_input(true)


func open() -> void:
	visible = true
	sel = 0
	queue_redraw()


func close() -> void:
	visible = false
	if video:
		video.save_cfg()
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible or video == null:
		return
	var act := ""
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP, KEY_W:     act = "up"
			KEY_DOWN, KEY_S:   act = "down"
			KEY_LEFT, KEY_A:   act = "left"
			KEY_RIGHT, KEY_D:  act = "right"
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: act = "ok"
			KEY_ESCAPE:        act = "back"
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_UP:    act = "up"
			JOY_BUTTON_DPAD_DOWN:  act = "down"
			JOY_BUTTON_DPAD_LEFT:  act = "left"
			JOY_BUTTON_DPAD_RIGHT: act = "right"
			JOY_BUTTON_A:          act = "ok"
			JOY_BUTTON_B:          act = "back"
	if act == "":
		return
	get_viewport().set_input_as_handled()
	match act:
		"up":    sel = posmod(sel - 1, N)
		"down":  sel = posmod(sel + 1, N)
		"left":  _cycle(-1)
		"right": _cycle(1)
		"ok":
			if sel == Row.BACK:
				close()
			else:
				_cycle(1)
		"back":  close()
	queue_redraw()


func _cycle(step: int) -> void:
	match sel:
		Row.SIZE:
			var list: Array = video.sizes()
			var at: int = list.find(video.size)
			video.size = list[posmod((at if at >= 0 else 0) + step,
				list.size())]
		Row.MODE:
			video.mode = posmod(int(video.mode) + step,
				_Video.MODE_NAME.size())
		Row.AA:
			video.aa = posmod(video.aa + step, _Video.AA_NAME.size())
		Row.VSYNC:
			video.vsync = not video.vsync
		Row.FPS:
			var at: int = _Video.FPS.find(video.fps_cap)
			video.fps_cap = int(_Video.FPS[posmod((at if at >= 0 else 0)
				+ step, _Video.FPS.size())])
		Row.BACK:
			return
	video.apply()
	video.save_cfg()


func _value(row: int) -> String:
	match row:
		Row.SIZE:  return video.size_name()
		Row.MODE:  return str(_Video.MODE_NAME[int(video.mode)])
		Row.AA:    return str(_Video.AA_NAME[clampi(video.aa, 0,
			_Video.AA_NAME.size() - 1)])
		Row.VSYNC: return "on" if video.vsync else "off"
		Row.FPS:   return video.fps_name()
	return ""


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if video == null:
		return
	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.78), true)

	var w := 460.0
	var h := 30.0 * float(N) + 128.0
	var x := maxf(12.0, vp.x * 0.5 - w * 0.5)
	var y := maxf(20.0, (vp.y - h) * 0.4)
	draw_rect(Rect2(x, y, w, h), Color(0.04, 0.04, 0.06, 0.96), true)
	draw_rect(Rect2(x, y, w, h), Color(1, 0.85, 0.2, 0.35), false, 1.0)

	var tx := x + 24.0
	var ty := y + 42.0
	var title := "VIDEO"
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	draw_string_outline(font, Vector2(x + w * 0.5 - tw * 0.5, ty), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 4, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(x + w * 0.5 - tw * 0.5, ty), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.88, 0.3))
	ty += 30.0

	for i in N:
		var on := i == sel
		if on:
			draw_rect(Rect2(x + 12, ty - 2, w - 24, 26),
				Color(0.9, 0.75, 0.15, 0.2), true)
		draw_string(font, Vector2(tx, ty + 17), ROW_NAME[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color(1, 0.9, 0.4) if on else Color(0.85, 0.85, 0.88))
		if i != Row.BACK:
			var v := "< %s >" % _value(i) if on else _value(i)
			draw_string(font, Vector2(tx + 190, ty + 17), v,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				Color(0.75, 0.92, 1.0) if on else Color(0.55, 0.7, 0.85))
		ty += 30.0

	ty += 10.0
	# The two things a player will otherwise think are bugs.
	var note := "resolution applies to windowed and borderless"
	if int(video.mode) == _Video.Mode.FULLSCREEN:
		note = "fullscreen uses the whole screen; pick windowed to set a size"
	draw_string(font, Vector2(tx, ty), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(0.55, 0.55, 0.6))
	ty += 16.0
	draw_string(font, Vector2(tx, ty),
		"8x is the highest MSAA the renderer has; the last step supersamples",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.45, 0.5))
	ty += 16.0
	draw_string(font, Vector2(tx, ty),
		"W/S or d-pad move   A/D or left/right change   ESC back",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.55))
