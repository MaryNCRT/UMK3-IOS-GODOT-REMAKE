## The button pictures, from the Kenney-style packs under `Source/`.
##
## Five sets ship: a keyboard and four pads. **The Alt variant of each** is the
## one used, which is the flat outlined style rather than the shaded one, and
## it is the only style that reads at the size the input panel draws.
##
## The naming is regular enough to build a path from a binding:
##
##     keyboard   T_<KEY>_Key_Alt.png              99 keys
##     PS5        T_P5_<BTN>_Alt.png
##     PS4        T_P4_<BTN>_Alt.png
##     Xbox       T_X_<BTN>_Alt.png    faces are  T_X_A_White_Alt.png
##     Switch     T_S_<BTN>_Alt.png
##
## A binding that has no picture falls back to its NAME, drawn as text, so a
## key nobody made a glyph for still tells the player what to press.
##
## ## No asset ships here
##
## `assets/` is gitignored, and these are the user's own copies of the packs.
class_name UMK3Glyphs
extends RefCounted

const DIR := "res://assets/controls"

## Godot key -> the middle of the keyboard file name. Only the keys a fighting
## game would ever be bound to; anything else falls back to text.
const KEY_FILE := {
	KEY_A: "A", KEY_B: "B", KEY_C: "C", KEY_D: "D", KEY_E: "E", KEY_F: "F",
	KEY_G: "G", KEY_H: "H", KEY_I: "I", KEY_J: "J", KEY_K: "K", KEY_L: "L",
	KEY_M: "M", KEY_N: "N", KEY_O: "O", KEY_P: "P", KEY_Q: "Q", KEY_R: "R",
	KEY_S: "S", KEY_T: "T", KEY_U: "U", KEY_V: "V", KEY_W: "W", KEY_X: "X",
	KEY_Y: "Y", KEY_Z: "Z",
	KEY_0: "0", KEY_1: "1", KEY_2: "2", KEY_3: "3", KEY_5: "5", KEY_6: "6",
	KEY_7: "7", KEY_8: "8", KEY_9: "9",
	KEY_UP: "Arrow_Up", KEY_DOWN: "Arrow_Down", KEY_LEFT: "Arrow_Left",
	KEY_RIGHT: "Arrow_Right",
	KEY_SPACE: "Space", KEY_ENTER: "Enter", KEY_SHIFT: "Shift",
	KEY_CTRL: "Ctrl", KEY_ALT: "Alt", KEY_TAB: "Tab", KEY_ESCAPE: "Esc",
	KEY_BACKSPACE: "BackSpace",
}

## Joypad button -> the middle of the file name, per set. Godot's numbering is
## Xbox-lettered, so the PlayStation and Switch names are a relabelling of the
## same button rather than a different button.
const PAD_FILE := {
	"ps5": {
		JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle",
		JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle",
		JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1",
		JOY_BUTTON_DPAD_UP: "Dpad_UP", JOY_BUTTON_DPAD_DOWN: "Dpad_Down",
		JOY_BUTTON_DPAD_LEFT: "Dpad_Left",
		JOY_BUTTON_DPAD_RIGHT: "Dpad_Right",
		JOY_BUTTON_START: "Options", JOY_BUTTON_BACK: "Share",
	},
	"ps4": {
		JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle",
		JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle",
		JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1",
		JOY_BUTTON_DPAD_UP: "Dpad_UP", JOY_BUTTON_DPAD_DOWN: "Dpad_Down",
		JOY_BUTTON_DPAD_LEFT: "Dpad_Left",
		JOY_BUTTON_DPAD_RIGHT: "Dpad_Right",
		JOY_BUTTON_START: "Options", JOY_BUTTON_BACK: "Share",
	},
	"xbox": {
		JOY_BUTTON_A: "A_White", JOY_BUTTON_B: "B_White",
		JOY_BUTTON_X: "X_White", JOY_BUTTON_Y: "Y_White",
		JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
		JOY_BUTTON_DPAD_UP: "Dpad_Up", JOY_BUTTON_DPAD_DOWN: "Dpad_Down",
		JOY_BUTTON_DPAD_LEFT: "Dpad_Left",
		JOY_BUTTON_DPAD_RIGHT: "Dpad_Right",
		JOY_BUTTON_BACK: "Share",
	},
	"switch": {
		JOY_BUTTON_A: "B", JOY_BUTTON_B: "A",        # Nintendo swaps them
		JOY_BUTTON_X: "Y", JOY_BUTTON_Y: "X",
		JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
		JOY_BUTTON_DPAD_UP: "Dpad_Up", JOY_BUTTON_DPAD_DOWN: "Dpad_Down",
		JOY_BUTTON_DPAD_LEFT: "Dpad_Left",
		JOY_BUTTON_DPAD_RIGHT: "Dpad_Right",
		JOY_BUTTON_START: "Plus", JOY_BUTTON_BACK: "Minus",
	},
}

const PREFIX := {"ps5": "T_P5_", "ps4": "T_P4_", "xbox": "T_X_",
	"switch": "T_S_"}

var _memo := {}


## The picture for one keyboard key, or null.
func key(code: int) -> Texture2D:
	if not KEY_FILE.has(code):
		return null
	return _load("kb/T_%s_Key_Alt.png" % KEY_FILE[code])


## The picture for one pad button on one kind of pad, or null.
func button(kind: String, code: int) -> Texture2D:
	if not PAD_FILE.has(kind):
		return null
	var m: Dictionary = PAD_FILE[kind]
	if not m.has(code):
		return null
	return _load("%s/%s%s_Alt.png" % [kind, PREFIX[kind], m[code]])


## What to print when there is no picture.
static func key_name(code: int) -> String:
	if code == KEY_NONE:
		return "--"
	return OS.get_keycode_string(code)


static func button_name(code: int) -> String:
	if code < 0:
		return "--"
	match code:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_DPAD_UP: return "D-Up"
		JOY_BUTTON_DPAD_DOWN: return "D-Down"
		JOY_BUTTON_DPAD_LEFT: return "D-Left"
		JOY_BUTTON_DPAD_RIGHT: return "D-Right"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_BACK: return "Back"
	return "B%d" % code


func _load(rel: String) -> Texture2D:
	if _memo.has(rel):
		return _memo[rel]
	var path := DIR.path_join(rel)
	var tex: Texture2D = null
	# The packs are loose PNGs under `assets/`, which Godot does not import
	# when the folder carries a .gdignore -- so read the bytes rather than
	# asking the resource loader, the same way the game's own textures are
	# read. If it HAS been imported, take that instead; it is the same image.
	if ResourceLoader.exists(path):
		var r = load(path)
		if r is Texture2D:
			tex = r
	if tex == null and FileAccess.file_exists(path):
		var img := Image.new()
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			if img.load_png_from_buffer(f.get_buffer(f.get_length())) == OK:
				tex = ImageTexture.create_from_image(img)
			f.close()
	_memo[rel] = tex
	return tex
