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


## **The panel measures itself before it draws.**
##
## What was here put the background at a fixed 368 high and then drew however
## many rows there were, so the last two lines fell out of the bottom of it and
## sat on the stage -- which is what it looked like when the window was made
## bigger, because a bigger window means a taller viewport and a panel pinned
## to the top does not grow with it.
##
## So: lay it out into a list first, ask how tall that came to, paint the box,
## and then paint the list into it. It cannot overflow because the box is
## measured from the thing that goes inside it, and it is clamped into the
## viewport so it cannot hang off an edge either.
func _draw() -> void:
	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	var fs := _font_size

	var kind := "kb"
	var on_pad := false
	if input:
		kind = input.pad_kind(player)
		on_pad = input.device[player] >= 0

	# --- lay out -----------------------------------------------------------
	# Each entry is [kind, y, payload]. Nothing is painted yet.
	var rows: Array = []
	var h := 28.0
	for i in _Input.N:
		rows.append(["bit", h, i])
		h += 21.0
	h += 8.0
	rows.append(["head", h, "SPECIALS"])
	h += 16.0
	for sp in _Moves.SPECIALS:
		rows.append(["special", h, sp])
		h += 32.0
	h += 2.0
	rows.append(["note", h, "<- is AWAY from the opponent"])
	h += 15.0
	rows.append(["note", h, "ESC or START  pause and controls"])
	h += 12.0

	var w := 208.0
	var x := vp.x - w - 10.0
	# Clear of the bars and the round tokens under them.
	var y := 132.0
	# If the bars and the panel together are taller than the window -- a short
	# window, or one resized to a strip -- the panel comes up rather than off.
	if y + h > vp.y - 6.0:
		y = maxf(6.0, vp.y - 6.0 - h)

	# --- paint -------------------------------------------------------------
	draw_rect(Rect2(x, y, w, h), Color(0, 0, 0, 0.55), true)
	draw_rect(Rect2(x, y, w, h), Color(1, 1, 1, 0.15), false, 1.0)
	draw_string(font, Vector2(x + 10, y + 18), "P%d INPUT" % (player + 1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.85, 0.2))
	if on_pad:
		draw_string(font, Vector2(x + w - 48, y + 18), kind.to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, Color(0.5, 0.8, 1.0))

	for r in rows:
		var ry: float = y + float(r[1])
		match str(r[0]):
			"bit":
				# The ten lamps, in the ENGINE's bit order, each with what
				# produces it. An input that does not light here never reached
				# the state machine.
				var i: int = int(r[2])
				var on := (raw & (1 << i)) != 0
				if on:
					draw_rect(Rect2(x + 8, ry, w - 16, 20),
						Color(0.15, 0.6, 0.25, 0.9), true)
				draw_string(font, Vector2(x + 13, ry + 14), _Input.BITS[i],
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					Color(1, 1, 1) if on else Color(0.55, 0.55, 0.55))
				if input:
					_binding(font, Vector2(x + w - 64, ry), i, kind, on_pad,
						on, fs)
			"head":
				draw_string(font, Vector2(x + 10, ry), str(r[2]),
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.85, 0.2))
			"special":
				var sp: Dictionary = r[2]
				var hot: bool = _flash > 0 and sp["name"] == last_special
				draw_string(font, Vector2(x + 10, ry), sp["name"],
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 1,
					Color(0.3, 1.0, 0.4) if hot else Color(0.85, 0.85, 0.85))
				draw_string(font, Vector2(x + 16, ry + 14),
					_Moves.notation(sp["row"]),
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 1,
					Color(1, 0.9, 0.4) if hot else Color(0.6, 0.6, 0.6))
			"note":
				# Back and forward are relative to who you are facing, which is
				# the one thing a notation never says out loud.
				draw_string(font, Vector2(x + 10, ry), str(r[2]),
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2,
					Color(0.55, 0.55, 0.6))


## **What this player actually plays with, and only that.**
##
## Both columns at once was a leftover from when the keyboard stayed live
## behind a pad. It does not any more -- see umk3_input.gd's `read` -- so
## showing a W beside a d-pad would be showing a key that does nothing.
func _binding(font: Font, at: Vector2, bit: int, kind: String, on_pad: bool,
		lit: bool, fs: int) -> void:
	var tex: Texture2D = null
	var text := ""
	if on_pad:
		var btn: int = int(input.pad[player][bit])
		tex = glyphs.button(kind, btn)
		text = _Glyphs.button_name(btn)
	else:
		var key: int = int(input.keys[player][bit])
		tex = glyphs.key(key)
		text = _Glyphs.key_name(key)
	if tex:
		draw_texture_rect(tex, Rect2(at.x + 26, at.y + 1, 18, 18), false)
		return
	draw_string(font, Vector2(at.x + 16, at.y + 14), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2,
		Color(1, 0.9, 0.4) if lit else Color(0.45, 0.45, 0.45))
