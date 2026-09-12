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
## True when this player named a pad that is not plugged in, so the menu can
## say that what he is holding is not what he asked for.
var missing := [false, false]

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
## **A device, always.** No automatic: `KB` or a named pad, nothing else.
var pref := [KB, KB]
## Which pictures to draw for each player's pad, or "" to use what was
## detected. See `cycle_style`.
var style := [STYLE_AUTO, STYLE_AUTO]


func _init() -> void:
	reset()
	load_cfg()


func reset() -> void:
	keys = [DEFAULT_KEYS[0].duplicate(), DEFAULT_KEYS[1].duplicate()]
	pad = [DEFAULT_PAD.duplicate(), DEFAULT_PAD.duplicate()]


## Hand out the pads. Called every frame, so hot-plugging is picked up without
## restarting, but **nothing is assigned on its own**.
##
## There is no "automatic" any more. A player names a device and gets that
## device or nothing, which is the only arrangement where two people can sit
## down and be sure which stick is theirs: an automatic rule that hands out
## whatever is going reassigns itself the moment somebody plugs a headset dongle
## in, and you find out mid-round.
##
## **A pad belongs to one player at a time.** Two people on one stick is not a
## two-player game -- every press would arrive twice, once as each of them -- so
## a pad already claimed by the other player is skipped. The KEYBOARD is not
## like that: it is always live for both, because the two default layouts do not
## overlap and somebody has to be able to join in without unplugging anything.
func detect() -> void:
	var pads := Input.get_connected_joypads()
	var taken := {}
	for i in 2:
		device[i] = -1
		missing[i] = false
	for i in 2:
		if pref[i] == KB or pref[i] == "":
			continue
		var got := false
		for d in pads:
			if not taken.has(d) and ident(int(d)) == pref[i]:
				device[i] = int(d)
				taken[d] = true
				got = true
				break
		# Named a pad and it is not there. The keyboard still answers, and the
		# menu says the choice could not be honoured rather than pretending.
		missing[i] = not got


## The choices a player can be offered, in the order the menu cycles them: the
## keyboard, then one entry per connected pad. A pad the OTHER player has
## claimed is left out, so the list cannot offer a conflict.
func choices(player: int) -> Array:
	var out := [KB]
	for d in Input.get_connected_joypads():
		var id := ident(int(d))
		if id == pref[1 - player]:
			continue
		out.append(id)
	# A named pad that is unplugged stays on the list, or cycling away from it
	# would silently throw the choice away.
	if pref[player] != KB and pref[player] != "" and not out.has(pref[player]):
		out.append(pref[player])
	return out


## Does this player have a pad in his hands right now?
func has_pad(player: int) -> bool:
	return device[player] >= 0


## What to print for one of those choices.
func choice_name(which: String) -> String:
	if which == KB or which == "":
		return "keyboard only"
	for d in Input.get_connected_joypads():
		if ident(int(d)) == which:
			return Input.get_joy_name(int(d))
	return "pad not connected"


## Move one player to the next device. `choices` has already left out whatever
## the other player claimed, so there is nothing to refuse here.
func cycle(player: int, step: int) -> void:
	var list := choices(player)
	var at := list.find(pref[player])
	if at < 0:
		at = 0
	pref[player] = str(list[posmod(at + step, list.size())])
	detect()
	save_cfg()


## **The glyph style, and it is an override rather than a setting.**
##
## `kind_of` gets a DualSense right off the product id, but a pad behind a
## third-party driver, an adapter or a Steam wrapper can arrive with no ids and
## a name that says nothing -- and then it is drawn with Xbox faces because
## that is what Godot's numbering is. This is the escape hatch for that case:
## say which pictures to draw and be done with it.
##
## Only offered to a player who actually HAS a pad. There is nothing to
## override on a keyboard.
const STYLE_AUTO := ""
const STYLES := [STYLE_AUTO, "ps5", "ps4", "xbox", "switch"]
const STYLE_NAME := {"": "auto (detected)", "ps5": "PlayStation 5",
	"ps4": "PlayStation 4", "xbox": "Xbox", "switch": "Nintendo"}


func cycle_style(player: int, step: int) -> void:
	if not has_pad(player):
		return
	var at := STYLES.find(style[player])
	if at < 0:
		at = 0
	style[player] = str(STYLES[posmod(at + step, STYLES.size())])
	save_cfg()


func style_name(player: int) -> String:
	var k: String = style[player]
	if k == STYLE_AUTO:
		return "auto (%s)" % pad_kind(player).to_upper()
	return str(STYLE_NAME.get(k, k))


## The ten-bit word for one player. **This is the only place a key or a button
## turns into an engine bit.**
##
## **One device at a time.** A player who has chosen a pad is not also moved by
## the keyboard: two hands on one fighter is how somebody else's WASD walks
## your man into a sweep. The keyboard answers when it is what he CHOSE, and
## when the pad he chose is not plugged in -- having nothing at all is not a
## useful way to be right.
func read(player: int) -> int:
	var w := 0
	var dev: int = device[player]
	if dev < 0:
		var k: Array = keys[player]
		for i in N:
			if int(k[i]) != KEY_NONE and Input.is_key_pressed(int(k[i])):
				w |= 1 << i
		return w

	var b: Array = pad[player]
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


## Which glyph set to DRAW for a player, which is not the same question as
## what he is holding: with nothing plugged in the pad column still has to say
## something, and Godot's button numbering is Xbox-lettered whatever is
## connected -- so an Xbox face is the honest picture of button 0.
func pad_glyphs(player: int) -> String:
	if style[player] != STYLE_AUTO:
		return str(style[player])
	var k := pad_kind(player)
	return "xbox" if k == KB else k


## Which kind of pad player `player` is holding, as a glyph-set name.
func pad_kind(player: int) -> String:
	var dev: int = device[player]
	if dev < 0:
		return KB
	return kind_of(dev)


## **The product id first, the name second.**
##
## A DualSense does not reliably say "DualSense". Depending on the driver, the
## cable and whether Steam is in the way, Windows reports it as "PS5
## Controller", as "Wireless Controller" -- which is also what a DualShock 4
## calls itself -- or as a generic XInput pad. Matching on the name alone got a
## PS5 pad drawn with PS4 faces, or with Xbox ones.
##
## `get_joy_info` carries `vendor_id` and `product_id` when the pad came in on
## the SDL path, and those are not ambiguous:
##
##     Sony        0x054c
##       0x0ce6      DualSense
##       0x0df2      DualSense Edge
##       0x05c4      DualShock 4        (first revision)
##       0x09cc      DualShock 4        (second)
##       0x0ba0      DualShock 4 dongle
##     Nintendo    0x057e
##
## An XInput pad reports no ids, which is itself the answer: XInput is the Xbox
## path, so Xbox faces are right for it.
static func kind_of(dev: int) -> String:
	var info := Input.get_joy_info(dev)
	var vid := int(info.get("vendor_id", 0))
	var pid := int(info.get("product_id", 0))
	if vid == 0x054c:
		if pid == 0x0ce6 or pid == 0x0df2:
			return "ps5"
		return "ps4"
	if vid == 0x057e:
		return "switch"

	var nm := Input.get_joy_name(dev).to_lower()
	if nm.find("dualsense") >= 0 or nm.find("ps5") >= 0:
		return "ps5"
	if nm.find("dualshock") >= 0 or nm.find("ps4") >= 0:
		return "ps4"
	if nm.find("wireless controller") >= 0:
		return "ps4"
	if nm.find("pro controller") >= 0 or nm.find("switch") >= 0:
		return "switch"
	if nm.find("joy-con") >= 0:
		return "switch"
	return "xbox"


## The name to print for whatever a player ended up holding.
func device_name(player: int) -> String:
	var dev: int = device[player]
	if dev < 0:
		return "keyboard"
	return Input.get_joy_name(dev)


# --------------------------------------------------------------- persistence
func save_cfg() -> void:
	var c := ConfigFile.new()
	for p in 2:
		for i in N:
			c.set_value("keys%d" % p, BITS[i], int(keys[p][i]))
			c.set_value("pad%d" % p, BITS[i], int(pad[p][i]))
		c.set_value("device", "p%d" % p, str(pref[p]))
		c.set_value("device", "style%d" % p, str(style[p]))
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
		# An empty pref is a file written before the automatic option was
		# taken out; it means keyboard now.
		if pref[p] == "":
			pref[p] = KB
		style[p] = str(c.get_value("device", "style%d" % p, style[p]))
