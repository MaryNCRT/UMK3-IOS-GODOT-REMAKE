## The input panel: which keys are down, and how each special is done.
##
## Down the right-hand side, because that is where it does not cover the fight.
##
## The ten lamps are the ENGINE'S ten bits, in the engine's own order -- four
## directions then HP, LP, BL, HK, LK, RUN -- so what lights up is exactly what
## the fight receives. That is the point of showing it: an input that does not
## light here never reached the state machine, and one that lights and does
## nothing is a bug in the fight rather than in the keyboard.
##
## The move list underneath is the game's own notation out of
## `_Scorpion_Moves6`. See umk3_moves.gd.
extends Control

const _Moves := preload("res://umk3/umk3_moves.gd")

## The ten bits, with the key that produces each for player one.
const LAMPS := [
	["UP", "W"], ["DOWN", "S"], ["LEFT", "A"], ["RIGHT", "D"],
	["HP", "U"], ["LP", "I"], ["BL", "O"], ["HK", "J"], ["LK", "K"],
	["RUN", "L"],
]

var raw := 0
var last_special := ""
var _flash := 0

var _font_size := 13


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


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
	var w := 186.0
	var x := vp.x - w - 10.0
	var y := 96.0
	var font := ThemeDB.fallback_font
	var fs := _font_size

	# The panel, dark enough to read over a stage but not a wall.
	draw_rect(Rect2(x, y, w, 292), Color(0, 0, 0, 0.55), true)
	draw_rect(Rect2(x, y, w, 292), Color(1, 1, 1, 0.15), false, 1.0)

	draw_string(font, Vector2(x + 10, y + 18), "INPUT",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.85, 0.2))

	# Ten lamps, in the engine's bit order.
	var ly := y + 30.0
	for i in LAMPS.size():
		var on := (raw & (1 << i)) != 0
		var row := Rect2(x + 10, ly, w - 20, 15)
		if on:
			draw_rect(row, Color(0.15, 0.6, 0.25, 0.9), true)
		draw_string(font, Vector2(x + 14, ly + 12), LAMPS[i][0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(1, 1, 1) if on else Color(0.55, 0.55, 0.55))
		draw_string(font, Vector2(x + w - 34, ly + 12), LAMPS[i][1],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(1, 0.9, 0.4) if on else Color(0.45, 0.45, 0.45))
		ly += 16.0

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
