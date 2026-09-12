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

## The sentinel `pref` value for "keyboard only".
const KB := "kb"

## **A pad binding above this is an AXIS, not a button.**
##
## Windows drives Xbox-compatible pads through XInput, and XInput does not
## report the triggers as buttons at all -- they are analogue axes, so
## `InputEventJoypadButton` never fires for LT or RT and a menu that only
## listens for buttons cannot bind them. Godot sends them as
## `InputEventJoypadMotion` on JOY_AXIS_TRIGGER_LEFT and _RIGHT instead.
##
## So an axis is encodable as a binding: AXIS + axis * 2 + (1 if the useful
## direction is positive). That covers the sticks as well, which is the same
## problem one layer up.
const AXIS := 1000
## How far an axis has to move to count as pressed. The triggers rest at 0.
const AXIS_ON := 0.5


## **What identifies a pad across a restart.**
##
## `get_joy_guid` is the right answer for anything on the SDL path -- a
## DualSense, a DualShock, a Pro Controller -- but on Windows every
## Xbox-compatible pad comes through XInput and Godot reports the GUID
## `__XINPUT_DEVICE__` for ALL of them. Two Xbox pads would be the same string
## and a saved choice would be meaningless.
##
## `get_joy_info` carries `xinput_index` for exactly those, which is the slot
## the driver gave it and is stable while it stays plugged into the same port.
## That is the best identity available; the name is the last resort.
static func ident(d: int) -> String:
	var g := Input.get_joy_guid(d)
	if g != "" and g != "__XINPUT_DEVICE__":
		return g
	var info := Input.get_joy_info(d)
	if info.has("xinput_index"):
		return "xinput:%d" % int(info["xinput_index"])
	return "pad:%s" % Input.get_joy_name(d)


## Is one binding down on one pad? Buttons and axes, by the same code.
static func pad_down(dev: int, code: int) -> bool:
	if code < 0:
		return false
	if code < AXIS:
		return Input.is_joy_button_pressed(dev, code)
	@warning_ignore("integer_division")
	var ax := (code - AXIS) / 2
	var positive := (code - AXIS) % 2 == 1
	var v := Input.get_joy_axis(dev, ax)
	return v > AXIS_ON if positive else v < -AXIS_ON

## The stick counts as the d-pad past this much deflection.
const DEADZONE := 0.5

## key[player][bit] and pad[player][bit].
var keys: Array = []
var pad: Array = []
## Which physical pad each player uses, or -1 for none. **Resolved every
## frame** by `detect()`; never set by hand.
var device := [-1, -1]

## What each player has CHOSEN, which is a different question from what he
## ended up with:
##
##     ""      automatic -- take whatever pad is going, in order
##     "kb"    keyboard only, leave the pads to the other player
##     a GUID  that model of pad and no other
##
## A GUID rather than an index because an index is whatever order the driver
## enumerated in this boot, and the whole point of saving a choice is that it
## survives the next one.
var pref := ["", ""]


func _init() -> void:
	reset()
	load_cfg()


func reset() -> void:
	keys = [DEFAULT_KEYS[0].duplicate(), DEFAULT_KEYS[1].duplicate()]
	pad = [DEFAULT_PAD.duplicate(), DEFAULT_PAD.duplicate()]


## Hand out the pads. Called every frame, so hot-plugging works without a menu.
##
## **A pad belongs to one player at a time.** Two people on one stick is not a
## two-player game -- every press would arrive twice, once as each of them --
## so a pad that is already taken is skipped rather than shared. The KEYBOARD
## is not like that: it is always live for both, because the two default
## layouts do not overlap and somebody has to be able to join in without
## unplugging anything.
##
## Explicit choices are honoured first and the automatic players take what is
## left, so choosing a pad for player two cannot be undone by player one
## happening to be enumerated first.
func detect() -> void:
	var pads := Input.get_connected_joypads()
	var taken := {}
	for i in 2:
		device[i] = -1
	for i in 2:
		if pref[i] == "" or pref[i] == KB:
			continue
		for d in pads:
			if not taken.has(d) and ident(int(d)) == pref[i]:
				device[i] = int(d)
				taken[d] = true
				break
	for i in 2:
		if pref[i] != "":
			continue
		for d in pads:
			if not taken.has(d):
				device[i] = int(d)
				taken[d] = true
				break


## The choices a player can be offered, in the order the menu cycles them:
## automatic, keyboard only, then one entry per connected pad.
func choices() -> Array:
	var out := ["", KB]
	for d in Input.get_connected_joypads():
		out.append(ident(int(d)))
	return out


## What to print for one of those choices.
func choice_name(which: String) -> String:
	if which == "":
		return "automatic"
	if which == KB:
		return "keyboard only"
	for d in Input.get_connected_joypads():
		if ident(int(d)) == which:
			return Input.get_joy_name(int(d))
	return "pad not connected"


## Move one player to the next choice, refusing to land on the pad the other
## player has explicitly claimed.
func cycle(player: int, step: int) -> void:
	var list := choices()
	var at := list.find(pref[player])
	if at < 0:
		at = 0
	for _i in list.size():
		at = posmod(at + step, list.size())
		var want: String = str(list[at])
		if want != "" and want != KB and want == pref[1 - player]:
			continue
		pref[player] = want
		break
	detect()
	save_cfg()


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
		if pad_down(dev, int(b[i])):
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
		c.set_value("device", "p%d" % p, str(pref[p]))
	c.save(CFG)


func load_cfg() -> void:
	var c := ConfigFile.new()
	if c.load(CFG) != OK:
		return
	for p in 2:
		for i in N:
			keys[p][i] = int(c.get_value("keys%d" % p, BITS[i], keys[p][i]))
			pad[p][i] = int(c.get_value("pad%d" % p, BITS[i], pad[p][i]))
		pref[p] = str(c.get_value("device", "p%d" % p, pref[p]))
