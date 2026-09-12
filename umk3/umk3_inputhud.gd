## The input panel: which bits are down, what produces each, and how the
## specials are done.
##
## Down the right-hand side, because that is where it does not cover the fight.
##
## The ten lamps are the ENGINE'S ten bits, in the engine's own order -- four
## directions then HP, LP, BL, HK, LK, RUN -- so what lights up is exactly what
## the fight receives. That is the point of showing it: an input that does not
## light here never reached the state machine, and one that lights and does
## nothing is a bug in the fight rather than in the keyboard.
##
## **What each bit is bound to comes from umk3_input.gd** and is drawn with the
## real button pictures, so the panel follows a rebind and follows a pad being
## plugged in without being told. A binding with no picture falls back to its
## name.
##
## The move list underneath is the game's own notation out of
## `_Scorpion_Moves6`. See umk3_moves.gd.
extends Control

const _Moves := preload("res://umk3/umk3_moves.gd")
const _Glyphs := preload("res://umk3/umk3_glyphs.gd")
const _Input := preload("res://umk3/umk3_input.gd")

var raw := 0
var last_special := ""
var _flash := 0
var _font_size := 13

## Set by umk3_main.gd. Without it the panel shows the lamps and no bindings,
## which is honest rather than a made-up default.
var input = null
var glyphs = null
## Which player's bindings to show.
var player := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyphs = _Glyphs.new()


## The fight hands us the word it actually received.
func set_state(bits: int, special: String) -> void:
	raw = bits
	if special != "":
		last_special = special
		_flash = 90
	elif _flash > 0:
		_flash -= 1
	queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	var w := 208.0
	var x := vp.x - w - 10.0
	var y := 96.0
	var font := ThemeDB.fallback_font
	var fs := _font_size

	# The panel, dark enough to read over a stage but not a wall.
	draw_rect(Rect2(x, y, w, 368), Color(0, 0, 0, 0.55), true)
	draw_rect(Rect2(x, y, w, 368), Color(1, 1, 1, 0.15), false, 1.0)

	var kind := "kb"
	var on_pad := false
	if input:
		kind = input.pad_kind(player)
		on_pad = input.device[player] >= 0
	draw_string(font, Vector2(x + 10, y + 18), "P%d INPUT" % (player + 1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.85, 0.2))
	if on_pad:
		draw_string(font, Vector2(x + w - 48, y + 18), kind.to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, Color(0.5, 0.8, 1.0))

	# Ten lamps, in the engine's bit order, each with what produces it.
	var ly := y + 28.0
	for i in _Input.N:
		var on := (raw & (1 << i)) != 0
		var row := Rect2(x + 8, ly, w - 16, 20)
		if on:
			draw_rect(row, Color(0.15, 0.6, 0.25, 0.9), true)
		draw_string(font, Vector2(x + 13, ly + 14), _Input.BITS[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(1, 1, 1) if on else Color(0.55, 0.55, 0.55))
		if input:
			_binding(font, Vector2(x + w - 64, ly), i, kind, on_pad, on, fs)
		ly += 21.0

	# The specials, in the game's own notation.
	ly += 8.0
	draw_string(font, Vector2(x + 10, ly), "SPECIALS",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.85, 0.2))
	ly += 16.0
	for sp in _Moves.SPECIALS:
		var hot: bool = _flash > 0 and sp["name"] == last_special
		draw_string(font, Vector2(x + 10, ly), sp["name"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 1,
			Color(0.3, 1.0, 0.4) if hot else Color(0.85, 0.85, 0.85))
		ly += 14.0
		draw_string(font, Vector2(x + 16, ly), _Moves.notation(sp["row"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 1,
			Color(1, 0.9, 0.4) if hot else Color(0.6, 0.6, 0.6))
		ly += 18.0

	# Back and forward are relative to who you are facing, which is the one
	# thing a notation never says out loud.
	draw_string(font, Vector2(x + 10, ly + 2),
		"<- is AWAY from the opponent", HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2,
		Color(0.55, 0.55, 0.6))
	draw_string(font, Vector2(x + 10, ly + 17),
		"ESC  pause and controls", HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2,
		Color(0.45, 0.45, 0.5))


## The key, and the pad button beside it when a pad is connected.
func _binding(font: Font, at: Vector2, bit: int, kind: String, on_pad: bool,
		lit: bool, fs: int) -> void:
	var key: int = int(input.keys[player][bit])
	var tex: Texture2D = glyphs.key(key)
	if tex:
		draw_texture_rect(tex, Rect2(at.x, at.y + 1, 18, 18), false)
	else:
		draw_string(font, Vector2(at.x, at.y + 14), _Glyphs.key_name(key),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2,
			Color(1, 0.9, 0.4) if lit else Color(0.45, 0.45, 0.45))
	if not on_pad:
		return
	var btn: int = int(input.pad[player][bit])
	var bt: Texture2D = glyphs.button(kind, btn)
	if bt:
		draw_texture_rect(bt, Rect2(at.x + 26, at.y + 1, 18, 18), false)
	else:
		draw_string(font, Vector2(at.x + 26, at.y + 14),
			_Glyphs.button_name(btn), HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 3,
			Color(1, 0.9, 0.4) if lit else Color(0.45, 0.45, 0.45))
