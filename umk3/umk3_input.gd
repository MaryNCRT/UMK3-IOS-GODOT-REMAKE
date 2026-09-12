## The input contract, the bindings, and which device each player is on.
##
## ## The ten bits are not negotiable
##
## `joy.c` proves the fight receives exactly ten bits in exactly this order --
## four directions, then HP, LP, BL, HK, LK, RUN -- and everything downstream
## reads that word: `TranslateJoybits`, the button tables at 0x00165584, the
## special sequences in `_seq_scorpion_*`. **What a player presses to produce a
## bit is the only part that is ours to choose**, and that is what this file is.
##
## ## One binding per bit per player, per device kind
##
## A player is on a keyboard or on a pad, and the two are kept separately so
## that plugging a pad in does not throw away a keyboard layout. Both are live
## at once: a bit is set if either source says so, which is what lets someone
## pick up a pad mid-round without going through a menu.
##
## ## Pads
##
## Godot normalises every pad to the same button numbers, so the engine side
## does not care what is plugged in -- what changes is only which GLYPH is
## drawn, and that is umk3_glyphs.gd's job. `Input.get_joy_name` is what says
## whether it is a DualSense, an Xbox pad, a DualShock or a Pro Controller.
##
## Settings live in `user://umk3_input.cfg`, outside the project.
class_name UMK3Input
extends RefCounted

## The ten bits, in the engine's own order. Index IS the bit.
const BITS := ["UP", "DOWN", "LEFT", "RIGHT", "HP", "LP", "BL", "HK", "LK",
	"RUN"]
const N := 10

## What each bit is called where a player can read it.
const LABEL := ["Up", "Down", "Left", "Right", "High punch", "Low punch",
	"Block", "High kick", "Low kick", "Run"]

const CFG := "user://umk3_input.cfg"

## The keyboard this build has always used: player one on the left hand plus
## U I O J K L, player two on the arrows and the keypad.
const DEFAULT_KEYS := [
	[KEY_W, KEY_S, KEY_A, KEY_D, KEY_U, KEY_I, KEY_O, KEY_J, KEY_K, KEY_L],
	[KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_KP_7, KEY_KP_8, KEY_KP_9,
		KEY_KP_4, KEY_KP_5, KEY_KP_6],
]

## The pad, in the arcade's own shape: the two punches on the top row, the two
## kicks on the bottom, block and run on the shoulders. Face buttons are
## Godot's numbering, which is Xbox-lettered whatever is plugged in.
const DEFAULT_PAD := [
	JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT,
	JOY_BUTTON_DPAD_RIGHT,
	JOY_BUTTON_Y,                     # high punch   triangle
	JOY_BUTTON_X,                     # low punch    square
	JOY_BUTTON_RIGHT_SHOULDER,        # block        R1
	JOY_BUTTON_B,                     # high kick    circle
	JOY_BUTTON_A,                     # low kick     cross
	JOY_BUTTON_LEFT_SHOULDER,         # run          L1
]

## The stick counts as the d-pad past this much deflection.
const DEADZONE := 0.5

## key[player][bit] and pad[player][bit].
var keys: Array = []
var pad: Array = []
## Which physical pad each player uses, or -1 for none.
var device := [-1, -1]


func _init() -> void:
	reset()
	load_cfg()


func reset() -> void:
	keys = [DEFAULT_KEYS[0].duplicate(), DEFAULT_KEYS[1].duplicate()]
	pad = [DEFAULT_PAD.duplicate(), DEFAULT_PAD.duplicate()]


## Hand out the connected pads: player one takes the first, player two the
## second. Called every frame, so hot-plugging works without a menu.
func detect() -> void:
	var found := Input.get_connected_joypads()
	for i in 2:
		device[i] = int(found[i]) if i < found.size() else -1


## The ten-bit word for one player. **This is the only place a key or a button
## turns into an engine bit.**
func read(player: int) -> int:
	var w := 0
	var k: Array = keys[player]
	var b: Array = pad[player]
	var dev: int = device[player]
	for i in N:
		if int(k[i]) != KEY_NONE and Input.is_key_pressed(int(k[i])):
			w |= 1 << i
	if dev < 0:
		return w
	for i in N:
		if int(b[i]) >= 0 and Input.is_joy_button_pressed(dev, int(b[i])):
			w |= 1 << i
	# The left stick doubles for the d-pad, which every fighting game does and
	# no menu should have to explain.
	var ax := Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
	var ay := Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
	if ay < -DEADZONE:
		w |= 1 << 0
	if ay > DEADZONE:
		w |= 1 << 1
	if ax < -DEADZONE:
		w |= 1 << 2
	if ax > DEADZONE:
		w |= 1 << 3
	return w


## Which kind of pad player `player` is holding, as a glyph-set name.
func pad_kind(player: int) -> String:
	var dev: int = device[player]
	if dev < 0:
		return "kb"
	var name := Input.get_joy_name(dev).to_lower()
	if name.find("dualsense") >= 0 or name.find("ps5") >= 0:
		return "ps5"
	if name.find("dualshock") >= 0 or name.find("ps4") >= 0 \
			or name.find("wireless controller") >= 0:
		return "ps4"
	if name.find("pro controller") >= 0 or name.find("switch") >= 0 \
			or name.find("joy-con") >= 0:
		return "switch"
	return "xbox"


# --------------------------------------------------------------- persistence
func save_cfg() -> void:
	var c := ConfigFile.new()
	for p in 2:
		for i in N:
			c.set_value("keys%d" % p, BITS[i], int(keys[p][i]))
			c.set_value("pad%d" % p, BITS[i], int(pad[p][i]))
	c.save(CFG)


func load_cfg() -> void:
	var c := ConfigFile.new()
	if c.load(CFG) != OK:
		return
	for p in 2:
		for i in N:
			keys[p][i] = int(c.get_value("keys%d" % p, BITS[i], keys[p][i]))
			pad[p][i] = int(c.get_value("pad%d" % p, BITS[i], pad[p][i]))
