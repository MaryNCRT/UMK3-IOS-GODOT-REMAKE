## The front end, recreated.
##
## ## Recreated, not ported -- and the difference matters
##
## The C project runs the ACTUAL decompiled front end: `Task_FEMain` from
## `decomp/gamecode/FrontEnd.c`, unmodified, driving sprites through the
## engine's own draw calls. That is a port.
##
## This is not that, and cannot be: the front end calls OpenGL directly and
## reads a 480x320 virtual screen, and putting Godot underneath it means
## either a GL 1.1 shim or editing the transcription. What is here is a menu
## with the same shape, built from **the game's own art** -- the title
## background, the logo, the marble menu plate, the button plates -- read live
## out of the user's `res` folder through our own PVRTC decoder.
##
## So the pictures are the game's. The layout is measured off those pictures
## by eye, and the text is rendered with a Godot font because the `.ft2` font
## format is documented but not yet ported. Both of those are stated in the
## README rather than left to be discovered.
##
## ## No game data ships here
extends Control

const _Tex := preload("res://umk3/umk3_textures.gd")
const UMK3Paths := preload("res://umk3/umk3_paths.gd")
## preload, not class_name: a class_name is invisible until the editor has
## indexed the project, and that is exactly when a fresh checkout runs.
const UMK3StageList := preload("res://umk3/umk3_stagelist.gd")

## The art is authored for 1024x768 inside a 1024x1024 power-of-two texture.
## The unused strip below is black in some sheets and magenta in others -- the
## exporter marked it so an accidental draw would be unmissable.
const ART := Vector2(1024.0, 768.0)

enum Screen { TITLE, MAIN, STAGES }

var res_dir := ""
var textures = null

var _screen := Screen.TITLE
var _bg := TextureRect.new()
var _logo := TextureRect.new()
var _rows := VBoxContainer.new()
var _hint := Label.new()

signal play_stage(stem: String)


func _ready() -> void:
	res_dir = UMK3Paths.resolve(res_dir)
	if res_dir == "":
		push_error("Set the res folder: your own extracted UMK3.app/res. "
			+ "No game data ships with this project.")
		return
	textures = _Tex.new(res_dir)

	set_anchors_preset(Control.PRESET_FULL_RECT)

	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_bg)

	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_logo)

	_rows.alignment = BoxContainer.ALIGNMENT_CENTER
	_rows.add_theme_constant_override("separation", 10)
	add_child(_rows)

	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hint.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_hint)

	get_viewport().size_changed.connect(_layout)
	_show_title()


## The art is 1024x768; the window is whatever it is. Everything is placed in
## art coordinates and scaled once, so the menu keeps its proportions instead
## of stretching -- which is what the original does with its 480x320.
func _art_scale() -> float:
	var vp := get_viewport_rect().size
	return minf(vp.x / ART.x, vp.y / ART.y)


func _layout() -> void:
	var vp := get_viewport_rect().size
	var s := _art_scale()
	var org := (vp - ART * s) * 0.5

	_logo.position = org + Vector2(0.0, 40.0) * s
	_logo.size = Vector2(ART.x, 300.0) * s

	_rows.position = org + Vector2(ART.x * 0.5 - 190.0, 380.0) * s
	_rows.size = Vector2(380.0, 300.0) * s
	_rows.scale = Vector2(s, s)
	_rows.position = org + Vector2(ART.x * 0.5 - 190.0 * s, 380.0 * s)

	_hint.position = org + Vector2(0.0, 690.0) * s
	_hint.size = Vector2(ART.x * s, 40.0 * s)


func _tex(stem: String) -> Texture2D:
	if textures == null:
		return null
	return textures.get_texture(stem + ".???")


## A button on the game's own torn-paper plate.
func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(380, 54)
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", Color(0.10, 0.09, 0.08))
	b.add_theme_color_override("font_hover_color", Color(0.55, 0.05, 0.05))
	b.add_theme_color_override("font_pressed_color", Color(0.8, 0.1, 0.1))

	var plate := _tex("FE_BUTTONS_01")
	if plate:
		# The torn plate sits in the atlas's top-left; 420x86 covers the widest
		# one. Measured off the decoded sheet, not read from a table -- the
		# atlas has no manifest.
		var at := AtlasTexture.new()
		at.atlas = plate
		at.region = Rect2(8, 6, 410, 86)
		var sb := StyleBoxTexture.new()
		sb.texture = at
		sb.set_texture_margin_all(10)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.add_theme_stylebox_override("focus", sb)
	b.pressed.connect(cb)
	_rows.add_child(b)
	return b


func _show_title() -> void:
	_screen = Screen.TITLE
	for c in _rows.get_children():
		c.queue_free()
	_bg.texture = _tex("FE_TITLE_BG")
	_logo.texture = _tex("FE_MAINLOGO_EN")
	_logo.visible = true
	_hint.text = "PRESS ANY KEY"
	_layout()


func _show_main() -> void:
	_screen = Screen.MAIN
	for c in _rows.get_children():
		c.queue_free()
	_bg.texture = _tex("FE_MENU_PLAY")
	_logo.texture = _tex("FE_MAINLOGO_EN")
	_logo.visible = true
	_hint.text = ""
	await get_tree().process_frame
	_button("STAGE VIEWER", _show_stages)
	_button("BACK", _show_title)
	_button("QUIT", func(): get_tree().quit())
	_layout()


func _show_stages() -> void:
	_screen = Screen.STAGES
	for c in _rows.get_children():
		c.queue_free()
	_bg.texture = _tex("FE_BG_MARBLE")
	_logo.visible = false
	await get_tree().process_frame
	_hint.text = "UP / DOWN to choose, ENTER to view, ESC back"
	for i in UMK3StageList.STAGES.size():
		var stem: String = UMK3StageList.STAGES[i]
		_button(UMK3StageList.pretty(stem), func(): play_stage.emit(stem))
	_layout()


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo) \
			and not (e is InputEventMouseButton and e.pressed):
		return
	match _screen:
		Screen.TITLE:
			_show_main()
		Screen.MAIN:
			if e is InputEventKey and e.keycode == KEY_ESCAPE:
				_show_title()
		Screen.STAGES:
			if e is InputEventKey and e.keycode == KEY_ESCAPE:
				_show_main()
