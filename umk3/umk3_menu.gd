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

## Which of the two things the stage list was opened for: a fight, or the free
## camera. The shell reads it when the stage loads.
var viewer_mode := false

var _screen := Screen.TITLE
var _bg := TextureRect.new()
var _logo := TextureRect.new()
var _scroll := ScrollContainer.new()
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

	# **Anchored, not hand-placed.** The first version positioned and scaled the
	# button column by hand off a 1024x768 art size; eleven stage buttons then
	# ran off the bottom of the window at any size. A ScrollContainer between
	# anchors is the thing that cannot do that.
	_scroll.set_anchors_preset(Control.PRESET_CENTER)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_rows.alignment = BoxContainer.ALIGNMENT_CENTER
	_rows.add_theme_constant_override("separation", 8)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows)

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

	# **This Control hangs off a plain Node, so anchors give it nothing.**
	# PRESET_FULL_RECT only fills a parent that has a size, and a Node has
	# none -- which left this at 0x0 and the background invisible while every
	# child still drew. Set it explicitly rather than rely on the preset.
	position = Vector2.ZERO
	size = vp
	_bg.position = Vector2.ZERO
	_bg.size = vp

	var s := _art_scale()
	var org := (vp - ART * s) * 0.5

	# The logo keeps its place in the art; everything else is laid out against
	# the WINDOW, so it cannot leave it.
	var logo_h := 240.0 * s
	_logo.position = Vector2(org.x, org.y + 30.0 * s)
	_logo.size = Vector2(ART.x * s, logo_h)
	var top := _logo.position.y + logo_h

	var hint_h := 34.0 * s
	_hint.position = Vector2(0.0, vp.y - hint_h - 12.0 * s)
	_hint.size = Vector2(vp.x, hint_h)
	_hint.add_theme_font_size_override("font_size", int(maxf(14.0, 20.0 * s)))

	# Whatever is left between the logo and the hint, with a margin, and never
	# taller than the buttons actually need.
	var avail := maxf(_hint.position.y - top - 20.0 * s, 80.0)
	var want := _rows.get_combined_minimum_size().y
	var h := minf(avail, maxf(want, 60.0))
	var w := minf(vp.x * 0.7, 460.0 * s)

	_scroll.position = Vector2((vp.x - w) * 0.5, top + 10.0 * s)
	_scroll.size = Vector2(w, h)
	_rows.custom_minimum_size.x = w


func _tex(stem: String) -> Texture2D:
	if textures == null:
		return null
	return textures.get_texture(stem + ".???")


## A full-screen sheet, cropped to the part that is actually art.
##
## These are authored at 1024x768 and stored in a 1024x1024 power-of-two
## texture; the strip below is padding, black in some sheets and magenta in
## others. Drawing the whole texture stretches that padding across the bottom
## of the window, which is what the first version did.
func _sheet(stem: String) -> Texture2D:
	var src := _tex(stem)
	if src == null:
		return null
	var h: int = mini(int(ART.y), src.get_height())
	if src.get_height() <= h:
		return src
	var at := AtlasTexture.new()
	at.atlas = src
	at.region = Rect2(0, 0, src.get_width(), h)
	return at


## A button on the game's own torn-paper plate.
func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	# Sized from the window, not from a constant, so eleven of them still fit
	# on a small one.
	var s := _art_scale()
	b.custom_minimum_size = Vector2(0, maxf(34.0, 48.0 * s))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", int(maxf(15.0, 24.0 * s)))
	# White with a hard black outline, which stays readable whatever the plate
	# behind it turns out to be. The atlas has no manifest, so the plate region
	# below is measured off the decoded sheet by eye and could be off by a few
	# texels; the text must not depend on that.
	b.add_theme_color_override("font_color", Color(0.93, 0.90, 0.84))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.25))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.55, 0.1))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	b.add_theme_constant_override("outline_size", 5)

	var plate := _tex("FE_BUTTONS_01")
	if plate:
		# The torn plate sits in the atlas's top-left; 420x86 covers the widest
		# one. Measured off the decoded sheet, not read from a table -- the
		# atlas has no manifest.
		var at := AtlasTexture.new()
		at.atlas = plate
		at.region = Rect2(10, 8, 405, 88)
		var sb := StyleBoxTexture.new()
		sb.texture = at
		sb.set_texture_margin_all(12)
		# The plates are white art; without this they inherit whatever the
		# theme last set and come out muddy.
		sb.modulate_color = Color(0.72, 0.70, 0.66)
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
	_bg.texture = _sheet("FE_TITLE_BG")
	_logo.texture = _sheet("FE_MAINLOGO_EN")
	_logo.visible = true
	_hint.text = "PRESS ANY KEY"
	_layout()


func _show_main() -> void:
	_screen = Screen.MAIN
	for c in _rows.get_children():
		c.queue_free()
	_bg.texture = _sheet("FE_MENU_PLAY")
	_logo.texture = _sheet("FE_MAINLOGO_EN")
	_logo.visible = true
	_hint.text = ""
	await get_tree().process_frame
	_button("FIGHT", func(): _show_stages(false))
	_button("STAGE VIEWER", func(): _show_stages(true))
	_button("BACK", _show_title)
	_button("QUIT", func(): get_tree().quit())
	_layout()


func _show_stages(viewer := false) -> void:
	viewer_mode = viewer
	_screen = Screen.STAGES
	for c in _rows.get_children():
		c.queue_free()
	# FE_BG_MARBLE carries alpha -- it is an overlay, not a backdrop, and on
	# its own it leaves a black screen. FE_MENU_PLAY is the opaque plate.
	_bg.texture = _sheet("FE_MENU_PLAY")
	_logo.visible = false
	_logo.size = Vector2.ZERO
	await get_tree().process_frame
	if viewer_mode:
		_hint.text = "CHOOSE A STAGE TO EXPLORE   -   ESC BACK"
	else:
		_hint.text = "CHOOSE A STAGE TO FIGHT ON   -   ESC BACK"
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


## Jump to a screen: 0 title, 1 main, 2 stage list. For checking the layout.
func show_screen(n: int) -> void:
	match n:
		1: _show_main()
		2: _show_stages()
		3: _show_stages(true)
		_: _show_title()
