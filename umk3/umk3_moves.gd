## Scorpion's special moves: the notation, and the detector that matches it.
##
## ## The notation is DATA, not lore
##
## `_Scorpion_Moves6` is a table of 64-byte rows in `__DATA`, sixteen int32
## terminated by -1, and `MovesListTab` (0x0010d918) slices it into sections --
## the first is the character's own specials. `DrawMoveListIcons` (0x0001e60c)
## draws each value as one cell of the 4x4 `MOVES_ICONS.PNG` atlas, and cutting
## that image into sixteen names every value:
##
##     0 ->   1 <-   2 up   3 down   4 down-forward   5 down-back
##     6 HP   7 LP   8 HK   9 LK    10 Block  11 Run  15 +
##
## That was the last manual step in docs/MOVES-TABLES.md and it is done. Read
## through it, Scorpion's four rows come out as:
##
##     1 1 7      <- <- LP        the spear
##     3 1 6      down <- HP      the teleport punch
##     2 15 10    up + Block      the air throw
##     7          LP              (one symbol, close range -- the throw)
##
## and the arcade's notation for those three is Back Back LP, Down Back HP and
## Block in the air. **The table agrees with a game nobody here has played from
## a file nobody here wrote**, which is the check.
##
## ## Which animation each one plays
##
## From the engine's own streams -- see umk3_scorpion_ani.gd:
##
##     82  SCSPEAR       199..202
##     81  SCFLIPUNCH1, SCFLIPUNCH2, SCTELEPUNCH1   -- the teleport
##
## ## What is NOT here
##
## **`seq_lookup` is decompiled (all of playback.c is), and it settles this
## rather than leaving it open.** Bit 10 of the input word is not a motion a
## player made -- `TranslateJoybits` (mk3.c) says it is set from OUTSIDE the
## fight entirely, by whatever fills `joy[]` before `mk3_update` sees it,
## which on iOS is the touch UI's own special-move button. `seq_lookup` and
## `Playback_Update` (playback.c) just turn that request into a synthesised
## joystick word, gated on `RoundParam[0x34]`. There never was a "back back
## low punch" recogniser to be faithful to; the binary does not run one.
##
## So this detector, built from the notation table rather than from
## `seq_lookup`, is not standing in for a gap -- it is the right thing for a
## joystick or a pad, which is what this port targets. The SEQUENCES are the
## game's own data; the matching rule and the timing window (WINDOW below)
## are this port's, same as they would have to be even with `seq_lookup`
## fully read, since that function answers a different question (what
## button the touch UI meant) than the one a pad's motion input asks.
##
## ## No game data ships here
class_name UMK3Moves
extends RefCounted

## The alphabet, by its value in the table.
const SYM := {
	0: "->", 1: "<-", 2: "up", 3: "down", 4: "dn-fwd", 5: "dn-back",
	6: "HP", 7: "LP", 8: "HK", 9: "LK", 10: "BL", 11: "RUN", 15: "+",
}

enum { SP_NONE, SP_SPEAR, SP_TELEPUNCH, SP_AIRTHROW }

## Each special: its name, the row as it appears in `_Scorpion_Moves6`, the
## animation id, and how it is matched.
##
## `seq` is in the table's own symbols. A direction is RELATIVE to the fighter's
## facing when it is matched -- 1 is "back", which is left when facing right --
## because that is what a fighting game means by Back.
const SPECIALS := [
	{
		"id": SP_SPEAR,
		"name": "SPEAR",
		"row": [1, 1, 7],
		"ani": 82,
		"hold": false,
	},
	{
		"id": SP_TELEPUNCH,
		"name": "TELEPORT PUNCH",
		"row": [3, 1, 6],
		"ani": 81,
		"hold": false,
	},
	{
		"id": SP_AIRTHROW,
		"name": "AIR THROW",
		"row": [2, 15, 10],
		"ani": -1,          # no animation of its own in the ninja table
		"hold": true,       # up + block, pressed together in the air
	},
]

## How many game frames a notation may take end to end.
##
## **A choice, and there is nothing decompiled left to defer it to.**
## `seq_lookup` is read now and it does not own a timing window at all -- it
## answers "what does touch-UI request N mean," not "how fast must this
## motion be." Half a second is the usual feel for this era; the buffer is
## cleared on a hit or a state change, which matters more than the exact
## number.
const WINDOW := 30


## One entry per input event, newest last.
class Buffer extends RefCounted:
	var syms := PackedInt32Array()
	var ages := PackedInt32Array()

	func push(sym: int) -> void:
		syms.append(sym)
		ages.append(0)
		if syms.size() > 12:
			syms.remove_at(0)
			ages.remove_at(0)

	func tick() -> void:
		var keep_s := PackedInt32Array()
		var keep_a := PackedInt32Array()
		for i in syms.size():
			var a := ages[i] + 1
			if a <= WINDOW:
				keep_s.append(syms[i])
				keep_a.append(a)
		syms = keep_s
		ages = keep_a

	func clear() -> void:
		syms = PackedInt32Array()
		ages = PackedInt32Array()

	## Does the buffer end with this sequence?
	func ends_with(seq: Array) -> bool:
		var want: Array = []
		for s in seq:
			if s != 15:                    # "+" is display furniture
				want.append(s)
		if want.size() > syms.size():
			return false
		var at := syms.size() - want.size()
		for i in want.size():
			if syms[at + i] != want[i]:
				return false
		return true


## Turn a raw ten-bit word into the table's symbols, for a fighter facing
## `facing`. Only what went DOWN this frame is an event.
static func events(raw: int, prev: int, facing: int) -> Array:
	var out: Array = []
	var went := raw & ~prev
	# Directions first, so "down, back" arrives in that order when both change.
	if went & 1:                                   # IN_UP
		out.append(2)
	if went & 2:                                   # IN_DOWN
		out.append(3)
	var left_sym := 1 if facing > 0 else 0
	var right_sym := 0 if facing > 0 else 1
	if went & 4:                                   # IN_LEFT
		out.append(left_sym)
	if went & 8:                                   # IN_RIGHT
		out.append(right_sym)
	if went & 16:
		out.append(6)                              # HP
	if went & 32:
		out.append(7)                              # LP
	if went & 64:
		out.append(10)                             # BL
	if went & 128:
		out.append(8)                              # HK
	if went & 256:
		out.append(9)                              # LK
	if went & 512:
		out.append(11)                             # RUN
	return out


## The special the buffer has just completed, or SP_NONE.
static func match_special(buf: Buffer, airborne: bool) -> Dictionary:
	for sp in SPECIALS:
		if sp["hold"]:
			continue                        # held combinations are not sequences
		if buf.ends_with(sp["row"]):
			return sp
	return {}


## The notation as text, for the on-screen guide.
static func notation(row: Array) -> String:
	var parts: Array[String] = []
	for s in row:
		parts.append(str(SYM.get(s, "?")))
	return " ".join(parts)
