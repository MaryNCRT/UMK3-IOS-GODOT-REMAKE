## The playable scene: two fighters, the engine's physics, and a camera.
##
## Ported from the C project's `runtime/fight_scene.c`, which is the file that
## says where each number comes from. What changes crossing over is WHAT RUNS
## the physics: there, `gravity_n_bounds` and `TranslateJoybits` are the
## decompiled functions themselves, compiled and called. Here there is no ARM
## and no decompiled C, so the same rules are transcribed into GDScript -- the
## adds and the clamps below are a reading of those functions, not the functions.
## That is the honest difference between the two builds and it is stated here
## rather than left to be discovered.
##
## ## What is measured and what is chosen
##
## The arena, the floor, the hitbox, the input contract and the physics are all
## out of the binary and marked so. The walk speed, the jump height, the damage,
## the move tempo and the starting gap are CHOSEN -- they live in per-character
## data tables that have not been extracted, and they are kept in one block so
## that when those tables are read there is one place to correct.
##
## ## No game data ships here
extends Node3D

const _Fighter := preload("res://umk3/umk3_fighter.gd")
const _Ani := preload("res://umk3/umk3_scorpion_ani.gd")
const _Moves := preload("res://umk3/umk3_moves.gd")

# ============================================================ measured data
#
# Everything in this section came out of the binary. Nothing here is a choice.

## mk3_init_game's defaults, before a level overrides them.
const ROUNDPARAM_LEFT := -550
const ROUNDPARAM_RIGHT := 950
const ROUNDPARAM_GROUND := 0x12c

## gravity_n_bounds: left = G[0xb0] + 0x3a, right = G[0xb4] + 0x15c + 3.
const WALL_L := ROUNDPARAM_LEFT + 0x3a                 # -492
const WALL_R := ROUNDPARAM_RIGHT - 399 + 0x15f         #  902

## mk3_update: G[0xac] = RoundParam[2] + 0xf7, every frame.
const FLOOR_Y := ROUNDPARAM_GROUND + 0xf7              #  547

## The hitbox.
##
## **`mk3_getbbox`'s 56 x 72 is not a fighter's box.** It is a wrapper around a
## function pointer with ONE animation patched past it -- `if (ani == 0x12be)`
## -- and those four numbers belong to that animation alone. The real boxes come
## from the pointer, which `mk3_init` receives as an argument and
## `GameInit_LoadABit` fills with `FrameID_GetBBox` (0x0001c674).
##
## That reads `_FrameInfo2` (0x00129f1c), sixteen bytes per GLOBAL frame id --
## the same id space as the animation streams -- as
##
##     left, top, width, height      right = left + width, bottom = top + height
##
## and the table is **almost entirely zero in the binary**: 27 of 7,168 entries.
## The rest is filled at run time. What ships is three nine-frame runs, and nine
## frames is a stance:
##
##     Kabal            left -20  top 9   54 x 135
##     Sub-Zero         left -18  top 8   56 x 128
##     Kitana/Jade/Mileena  left -29  top 6   55 x 130
##
## **So a fighter's box is about 55 wide and 130 tall**, not 72 tall. Against
## `_ochar_ground_offsets` -- Kabal 148, Sub-Zero 142, the kunoichi 139 -- the
## box is 90 to 93 per cent of the character's height.
##
## Scorpion's own rows are zero, so this uses the kunoichi's: they are the same
## 139 units tall and the same build. That is a stand-in, and a much closer one
## than a number belonging to a single patched animation.
const BOX_LEFT := -29
const BOX_TOP := 6
const BOX_W := 55
const BOX_H := 130

## The ten input bits. **This is the whole input contract** -- proved three
## ways, in the block at the top of decomp/gamecode/logic/joy.c.
const IN_UP := 1 << 0
const IN_DOWN := 1 << 1
const IN_LEFT := 1 << 2
const IN_RIGHT := 1 << 3
const IN_HP := 1 << 4
const IN_LP := 1 << 5
const IN_BL := 1 << 6
const IN_HK := 1 << 7
const IN_LK := 1 << 8
const IN_RUN := 1 << 9

## The five button tables, dumped from 0x00165584..0x00165624. The engine keeps
## a pointer to one of these in MK3OBJ + 0x60, and **that pointer IS which moves
## a fighter has** -- ducking is not a special case in the code, it is a
## different table.
enum { MV_NONE, MV_HI_PUNCH, MV_LO_PUNCH, MV_BLOCK, MV_HI_KICK, MV_LO_KICK,
	MV_UPPERCUT, MV_DUCK_PUNCH, MV_DUCK_BLOCK, MV_DUCK_KICKH, MV_DUCK_KICKL,
	MV_JUMP_PUNCH, MV_JUMP_KICK, MV_FLIP_PUNCH, MV_FLIP_KICK }

const BT_NULL := [0, 0, 0, 0, 0, 0]
const BT_STANCE := [MV_HI_PUNCH, MV_LO_PUNCH, MV_BLOCK, MV_HI_KICK,
	MV_LO_KICK, MV_NONE]
const BT_DUCK := [MV_UPPERCUT, MV_DUCK_PUNCH, MV_DUCK_BLOCK, MV_DUCK_KICKH,
	MV_DUCK_KICKL, MV_NONE]
const BT_JUMP := [MV_JUMP_PUNCH, MV_JUMP_PUNCH, MV_NONE, MV_JUMP_KICK,
	MV_JUMP_KICK, MV_NONE]
const BT_ANGLE_JUMP := [MV_FLIP_PUNCH, MV_FLIP_PUNCH, MV_NONE, MV_FLIP_KICK,
	MV_FLIP_KICK, MV_NONE]

const MOVE_NAME := ["", "hi punch", "lo punch", "block", "hi kick", "lo kick",
	"uppercut", "duck punch", "duck block", "duck kick h", "duck kick l",
	"jump punch", "jump kick", "flip punch", "flip kick"]

# ====================================================== CHOSEN, not measured
#
# Every number here lives in a per-character data table that has not been
# extracted.

const FX := 16                          ## 16.16, the engine's fixed point
const ONE := 1 << FX

## **The walk is MEASURED now, not chosen.** See WALK_FORWARD below.
## **The jump is measured now.** `t_do_jump_up` (0x000580e8) loads a literal
## into `obj->field20` and computes `obj->field24 = field20 + 0xa8000`, and
## `t_flight_call` (0x00055aec) copies the first into the part's 0x1c -- the y
## velocity -- and the second into 0x20, the gravity. The literal at 0x000581d0
## is -655360, which is exactly -10.0 in 16.16, and -10.0 + 0xa8000 is +0.5.
##
## So the jump velocity this port GUESSED at -10.0 was right, and the gravity it
## guessed at 0.40 was not: it is 0.5.
##
## (0xd in either field means "leave this one alone" -- a sentinel, not a value.)
const JUMP_VY := int(-10.0 * ONE)       ## measured, 0x000581d0
const GRAVITY := int(0.5 * ONE)         ## measured, field20 + 0xa8000
const JUMP_VX := int(6.0 * ONE)         ## an angled jump's horizontal speed

## **How long a move lasts is its animation's length**, and now that is the
## engine's own stream rather than a range read off the frame list.
const T_HIT := 16
const REACH_PUNCH := 70
const REACH_KICK := 86
const DAMAGE := 4

## How hard a hit pushes the victim back, and for how long.
##
## **Chosen.** The engine sends a struck fighter into a reaction state whose
## velocity comes from the move that hit him, and those live in the per-move
## states that are not decompiled. What IS measured is the shape: a reaction is
## a state with its own animation and no input, and it ends when the animation
## does -- which is why T_HIT is now the hit animation's own length rather than
## a number.
const KNOCKBACK := int(2.5 * ONE)
## Half the gap a round opens with. **Still chosen, and now visibly so.**
##
## At the old 1.946 scale 55 either side looked like a fight; at the real 1:1 it
## puts two 78-unit-wide models 110 apart, which is close enough to touch. The
## round-start code that holds the real number is not decompiled -- `init_players`
## (0x0005a418) sets up the slots but the positions are not in it.
var start_gap := 110

## The engine runs at a fixed rate and so does this: every duration in the
## fight is counted in FRAMES. Tying the tick to the display made every speed
## in the game three or four times too fast on a machine with vsync off.
const TICK_HZ := 60.0
const MAX_CATCHUP := 4

## A multiplier on the tick rate: the whole game's speed in one number.
##
## **The engine ticks once per drawn frame.** `UpdateArcadeCode` calls
## `mk3_update` exactly once -- its two call sites are the one-player and the
## multiplayer branches, not two ticks -- and its caller at 0x0002b15a runs it
## once a frame after the pause checks. There is no accumulator and no fixed
## step anywhere in that path.
##
## So the original's speed IS its frame rate, and that number lives in
## `-[EAGLView setAnimationInterval:]`, which is reached through objc_msgSend
## and has not been traced back to its caller. Every per-frame value measured so
## far -- 3.25 units of walk, 0.5 of gravity, a rate of 3 -- is per whatever
## that interval turns out to be.
##
## 60 is this port's assumption and not a reading. F10 and F11 move it live with
## the result in the HUD, so the feel can be dialled and the number reported
## back -- and then looked for in the binary knowing what it should be.
var game_speed := 1.0

# ============================== Scorpion's animations, by their engine id
#
# Every clip is now the engine's OWN stream out of `_nj_ani_data` -- see
# umk3_scorpion_ani.gd, which is generated from the binary rather than read off
# the frame list by eye. What is left here is only WHICH animation each state
# plays, and those are named by their contents.
#
# The hand-read ranges this replaces were wrong in ways that showed: a high
# punch played seven frames when the animation has three, and a hit reaction
# played 71, 72, 73 when the engine plays 72, 73, 72, 71 and comes back.

const ANI_STANCE := 0
const ANI_WALK_F := 1
const ANI_WALK_B := 2
const ANI_TURN := 3
const ANI_DUCK := 4
const ANI_DUCK_HIT := 7
const ANI_BLOCK := 12
const ANI_VICTORY := 13
const ANI_JUMP := 22
const ANI_JUMPFLIP := 26
const ANI_HIT := 28
const ANI_RUN := 70

## MV_* -> animation id. There is no SCJUMPPUNCH: the flip punch is the one
## airborne punch Scorpion has and stands in for both, which is a substitution
## and is said out loud rather than hidden.
const MOVE_ANI := [
	-1,          # MV_NONE
	14,          # MV_HI_PUNCH    SCHIPUNCH    3 frames
	15,          # MV_LO_PUNCH    SCLOPUNCH    3
	12,          # MV_BLOCK       SCBLOCK      3
	17,          # MV_HI_KICK     SCHIKICK     6
	18,          # MV_LO_KICK     SCLOKICK     6
	11,          # MV_UPPERCUT    SCUPPERCUT   5
	8,           # MV_DUCK_PUNCH  SCDUCKPUNCH  3
	6,           # MV_DUCK_BLOCK  SCDUCKBLOCK  3
	9,           # MV_DUCK_KICKH  SCDUCKHIKICK 4
	10,          # MV_DUCK_KICKL  SCDUCKLOKICK 3
	24,          # MV_JUMP_PUNCH  SCFLIPUNCH   3
	23,          # MV_JUMP_KICK   SCJUMPKICK   3
	24,          # MV_FLIP_PUNCH  SCFLIPUNCH   3
	25,          # MV_FLIP_KICK   SCFLIPKICK   3
]

## The animation rates, and the rule that picks them.
##
## **The engine does not give every animation a rate. It INHERITS.**
## `init_anirate` loads `Pp->field1c` and `next_anirate` counts it down, and
## only some states ever call `init_anirate`:
##
##     stance   6   `stance_setup` (0x000553c4): field40 = 0, get_char_ani,
##                  field1c = 6, init_anirate -- the one that was hardest to
##                  find, because nothing about a punch mentions it
##     walk     5   the other half of the walk table, per character
##     run      3   `run_setup` (0x00030fbc)
##
## A punch sets NO rate: `t_joy_hi_punch` writes `field40 = 0xe`, calls
## `get_char_ani` and never touches `init_anirate`. It plays at whatever the
## fighter was already on -- 6 standing, 5 walking. That is not a quirk to
## correct, it is the behaviour, so this reproduces it: the attack states pass
## the CURRENT rate rather than one of their own.
##
## This replaces a number chosen from the distribution of `init_anirate`
## literals across the whole binary. That distribution was a fair guess and it
## was a guess; 6 and the inheritance are what the code does.
const RATE_STANCE := 6
const RATE_RUN := 3

## Added to every rate, for dialling by eye. Zero is the engine. F8 and F9 move
## it; the HUD shows the stance's effective rate.
var rate_bias := 0

# ================================================== the walk, measured
#
# `_walk_forward_info` at 0x0016ef6c and `_walk_backward_info` at 0x0016f03c,
# eight bytes per character, indexed by `part->field24` -- the character number.
# `decode_walk_table` (0x000552dc) reads them:
#
#     entry[0]        -> obj->field1c, and init_anirate takes it as the RATE:
#                        one animation frame every N game frames
#     entry[1] << 4   -> obj->field20, the speed, in 16.16
#
# then `walk_flip_reverse` negates the speed when bit 4 of the part's 0x28 --
# the facing flag -- is set, and `get_walk_info_b` negates it once more, which
# is the whole of what makes backing up go the other way.
#
# State 0x45c of `plyrthread` calls the routine, calls `init_anirate`, copies
# the speed into 0x1c and calls `set_x_vel_player`. So both numbers come out of
# the same eight bytes, and the fight was using neither: 4.0 and 3.0 units a
# frame, chosen, against a real 3.25 and 2.25.
#
# Speeds are the raw 16.16 the engine holds, so nothing is converted twice.
const WALK_RATE := 0
const WALK_SPEED := 1
const WALK_FORWARD := [
	[5, 229376], [5, 196608], [5, 196608], [5, 212992], [5, 212992],
	[5, 196608], [5, 229376], [5, 212992], [5, 212992], [5, 212992],
	[5, 196608], [5, 196608], [5, 204800], [5, 204800], [5, 212992],
	[5, 212992], [5, 229376], [5, 212992], [5, 212992], [5, 212992],
	[5, 212992], [5, 212992], [5, 262144], [5, 327680], [4, 270336],
	[3, 327680],
]
const WALK_BACKWARD := [
	[5, 147456], [5, 147456], [5, 147456], [5, 147456], [5, 147456],
	[5, 147456], [5, 147456], [5, 147456], [5, 147456], [5, 147456],
	[5, 147456], [5, 147456], [5, 147456], [5, 147456], [5, 147456],
	[5, 147456], [5, 147456], [5, 147456], [5, 147456], [5, 147456],
	[5, 147456], [5, 147456], [5, 163840], [5, 196608], [4, 262144],
	[4, 262144],
]

## Which row of those tables this fight uses. 18 is SCORPION, from
## docs/ROSTER.md in the C project -- six independent readings agreeing.
const CHARACTER := 18

## How tall each fighter is, in engine units. `_ochar_ground_offsets` at
## 0x0016ef04, one int32 per character.
##
## **This is the scale between the engine's world and the stage's, and it is
## 1:1.** The port derived that scale from `mk3_getbbox`'s hard-coded 56 x 72
## box -- the only one in the binary, belonging to one animation -- and got
## 140.1 / 72 = 1.946. Against this table Scorpion is 139 units and the model
## measures 140.1, so one engine unit is one scene unit to within a per cent.
##
## The difference is not academic. At 1.946 the arena came out 2,713 scene units
## wide against Graveyard's 2,839-unit ground plane: the fighters could walk to
## the edge of the world, which is exactly what they did. At 1.008 the arena is
## 1,405 -- half the stage, centred, which is what an arena looks like.
##
## The ordering reads true as body heights: Shang Tsung 136, Kung Lao 140, Jax
## and Sheeva 158, Motaro 168, Shao Kahn 173.
const GROUND_OFFSET := [
	144, 143, 158, 144, 142, 147, 144, 147, 147, 140, 148, 158, 136,
	139, 147, 139, 139, 139, 139, 139, 139, 139, 139, 139, 168, 173,
]


enum St { STANCE, WALK_F, WALK_B, DUCK, BLOCK, JUMP, ATTACK, HIT, SPECIAL }

## The keyboard, the same map the C build uses: player one is the left hand
## plus U I O J K L, player two is the arrows and the numeric keypad.
const KEYS := [
	[KEY_W, KEY_S, KEY_A, KEY_D, KEY_U, KEY_I, KEY_O, KEY_J, KEY_K, KEY_L],
	[KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_KP_7, KEY_KP_8, KEY_KP_9,
		KEY_KP_4, KEY_KP_5, KEY_KP_6],
]


## One fighter's state. `x`, `y` and the velocities are the four words of GrObj
## the physics is made of: 0x0c, 0x10, 0x18, 0x1c, all 16.16, plus gravity at
## 0x20.
class Fight extends RefCounted:
	var x := 0
	var y := 0
	var vx := 0
	var vy := 0
	var g := 0

	var st := St.STANCE
	var timer := 0
	var timer_total := 0
	var move := 0
	var facing := 1
	var health := 100
	var connected := false
	var wins := 0
	var prev_buttons := 0
	var table: Array = BT_STANCE
	## The engine's animation clock, from `init_anirate` and `next_anirate`:
	## `ani_rate` game frames per animation frame, counted down in `ani_count`.
	var ani := -1                ## which animation, by its engine id
	var ani_rate := 5
	var ani_count := 1
	var ani_index := 0
	var node = null

	## The special-move input buffer, and which special is running.
	var buf = _Moves.Buffer.new()
	var special := 0
	var special_name := ""
	var raw_prev := 0

	## init_anirate: the rate is loaded and the countdown starts at ONE, so the
	## first advance lands on the very next frame rather than `rate` frames
	## later. Starting the same animation again is a no-op, which is what keeps
	## a held button from restarting the walk cycle every frame.
	func set_ani(id: int, rate: int) -> void:
		if id == ani:
			return
		ani = id
		# **-1 inherits.** A state that does not call `init_anirate` keeps the
		# countdown it was given, which is how a punch ends up playing at the
		# stance's 6 or the walk's 5 depending on how the fighter got there.
		if rate > 0:
			ani_rate = rate
		ani_count = 1
		ani_index = 0

	## next_anirate: decrement, and on reaching zero reload and step the frame.
	##
	## A looping animation wraps -- opcode 1 in the stream is a jump back to its
	## own start. A one-shot HOLDS its last frame: the stream ends there and the
	## state, not the animation, decides when to leave. That hold is the whole
	## of what stops a punch snapping back mid-swing.
	func tick_ani(count: int, loops: bool) -> bool:
		ani_count -= 1
		if ani_count > 0:
			return false
		ani_count = ani_rate
		if ani_index + 1 < count:
			ani_index += 1
		elif loops:
			ani_index = 0
		return true

	func xi() -> int:
		return x >> FX

	func yi() -> int:
		return y >> FX


var fighters: Array[Fight] = []
var scale_units := 1.0                  ## engine units -> scene units
var height := 1.0
var width := 1.0
var depth := 1.0
var error := ""
var frame := 0
var enabled := true
## Hold whatever pose was last set instead of driving one from the state. For
## `--pose`, which is how a clip range is checked against what it draws.
var frozen := false

## A scripted input, replacing the keyboard for one player.
##
## `--drive` sets it. A single word is held; a LIST is played one tick each and
## then holds the last -- which is what makes a special testable, since a
## notation is a sequence of edges and a held word has exactly one.
var forced := [-1, -1]
var forced_seq: Array = []
var _seq_at := 0

## Draw the hitboxes. H toggles it; `--hitbox 1` starts with it on.
##
## The body box is the engine's, from `_FrameInfo2` -- see BOX_W. The REACH bar
## in front of an attacking fighter is not: `REACH_PUNCH` and `REACH_KICK` are
## still chosen numbers, and drawing them next to a measured box is exactly how
## the difference stays visible instead of blending in.
var show_hitbox := false

var _boxes: Array[MeshInstance3D] = []
## What the input panel shows: the word player one's fighter actually received,
## and the special he just completed.
var last_raw := 0
var last_special := ""

var _accum := 0.0
var _cam: Camera3D = null
var audio = null
var _now := 0.0


func setup(res_dir: String, textures, cam: Camera3D, stem := "SCORPION_STANDARD") -> bool:
	_cam = cam
	for i in 2:
		var f := Fight.new()
		var n = _Fighter.new()
		add_child(n)
		# The second fighter is the same character, so it borrows the first
		# one's skin and posed meshes instead of reading and skinning them
		# again.
		if i > 0 and n.share(fighters[0].node):
			pass
		elif not n.load_character(res_dir, stem, textures):
			error = n.error
			return false
		f.node = n
		fighters.append(f)

	# The stance and the walk are every round's first two seconds. Taken from
	# the animations themselves, so the warm-up cannot drift from what plays.
	var warm := []
	for id in [ANI_STANCE, ANI_WALK_F, ANI_WALK_B]:
		for k in (_stream(id)[2] as Array):
			warm.append(k)
	fighters[0].node.prewarm(warm)

	# **The scale is derived from the character, not picked.** The engine says
	# a fighter is 72 units tall; the model says how tall it is in scene units.
	# One number joins a two-dimensional engine world to a 3D stage.
	height = fighters[0].node.height
	width = fighters[0].node.width
	depth = fighters[0].node.depth
	# **Against the character's own height, not the hitbox.** `mk3_getbbox`'s
	# 56 x 72 is one animation's hitbox and was the only height this port had;
	# `_ochar_ground_offsets` is the real one, per character, and it makes the
	# scale 1:1. See GROUND_OFFSET.
	# Metres per engine unit. The model is scaled to 1.8 m in the fighter, so
	# this is the same conversion on the other side: positions, the hitbox and
	# the camera all come out in metres.
	scale_units = _Fighter.FIGHTER_METRES / float(GROUND_OFFSET[CHARACTER])
	reset()
	return true


func reset() -> void:
	for i in fighters.size():
		var f := fighters[i]
		# The arena is 1,394 units wide and a fighter is 56 across, so starting
		# at the walls would put twenty-four body widths between them.
		@warning_ignore("integer_division")
		var mid := (WALL_L + WALL_R) / 2
		f.x = (mid + (start_gap if i == 1 else -start_gap)) * ONE
		f.y = (FLOOR_Y - BOX_H) * ONE
		f.vx = 0
		f.vy = 0
		f.g = 0
		f.st = St.STANCE
		f.timer = 0
		f.timer_total = 0
		f.move = MV_NONE
		f.facing = -1 if i == 1 else 1
		f.health = 100
		f.connected = false
		f.prev_buttons = 0
		f.table = BT_STANCE
		f.ani = -1
		f.ani_rate = WALK_FORWARD[CHARACTER][WALK_RATE]
		f.ani_count = 1
		f.ani_index = 0
	frame = 0


# --------------------------------------------------------------------- input
func _read_player(which: int) -> int:
	if which == 0 and not forced_seq.is_empty():
		var v: int = forced_seq[mini(_seq_at, forced_seq.size() - 1)]
		_seq_at += 1
		return v
	if forced[which] >= 0:
		return forced[which]
	var bits := 0
	var map: Array = KEYS[which]
	for i in 10:
		if Input.is_key_pressed(map[i]):
			bits |= 1 << i
	if which == 0:
		bits |= _read_pad()
	return bits


## A gamepad, as the same ten bits. The engine never sees a device: **it takes
## one ten-bit word per player and nothing else.**
func _read_pad() -> int:
	if Input.get_connected_joypads().is_empty():
		return 0
	var d := 0
	var pad: int = Input.get_connected_joypads()[0]
	var ax := Input.get_joy_axis(pad, JOY_AXIS_LEFT_X)
	var ay := Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y)
	if ay < -0.5 or Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_UP):
		d |= IN_UP
	if ay > 0.5 or Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_DOWN):
		d |= IN_DOWN
	if ax < -0.5 or Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_LEFT):
		d |= IN_LEFT
	if ax > 0.5 or Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_RIGHT):
		d |= IN_RIGHT
	if Input.is_joy_button_pressed(pad, JOY_BUTTON_Y):
		d |= IN_HP
	if Input.is_joy_button_pressed(pad, JOY_BUTTON_X):
		d |= IN_LP
	if Input.is_joy_button_pressed(pad, JOY_BUTTON_RIGHT_SHOULDER):
		d |= IN_BL
	if Input.is_joy_button_pressed(pad, JOY_BUTTON_B):
		d |= IN_HK
	if Input.is_joy_button_pressed(pad, JOY_BUTTON_A):
		d |= IN_LK
	if Input.is_joy_button_pressed(pad, JOY_BUTTON_LEFT_SHOULDER):
		d |= IN_RUN
	return d


## Which of the six buttons went down THIS frame, or -1.
##
## The C reads the translated bits out of G + 0x1c, because there the engine's
## own `TranslateJoybits` has already run. The button INDEX is the same 0..5
## either way, and here it comes straight off the raw word.
func _pressed_button(f: Fight, raw: int) -> int:
	var now := raw & 0x3F0                      # the six button bits, 4..9
	var went := now & ~f.prev_buttons
	f.prev_buttons = now
	for i in 6:
		if went & (1 << (4 + i)):
			return i
	return -1


# ----------------------------------------------------------- the state machine
func _move_frames(mv: int) -> int:
	if mv <= MV_NONE or mv >= MOVE_ANI.size():
		return RATE_STANCE
	# A move lasts its animation at whatever rate the fighter is carrying, which
	# is the inheritance the engine relies on.
	return _ani_length(MOVE_ANI[mv], maxi(1, RATE_STANCE + rate_bias))


func _move_reach(mv: int) -> int:
	match mv:
		MV_HI_KICK, MV_LO_KICK, MV_DUCK_KICKH, MV_DUCK_KICKL, MV_JUMP_KICK, \
		MV_FLIP_KICK:
			return REACH_KICK
		_:
			return REACH_PUNCH


func _start_attack(f: Fight, mv: int) -> void:
	f.st = St.ATTACK
	f.move = mv
	f.timer = _move_frames(mv)
	f.timer_total = f.timer
	f.connected = false
	if audio:
		audio.swing(mv == MV_UPPERCUT or mv == MV_HI_KICK or mv == MV_LO_KICK)


## The special the fighter just asked for, or an empty dictionary.
##
## **Bit 10 of the input word is the engine's own "a special was requested"**
## and it goes to `seq_lookup` -- 7,608 bytes of playback.c nobody has
## decompiled. This answers the same question from the notation tables instead;
## umk3_moves.gd says which half is the game's and which is mine.
func _special_asked(f: Fight, raw: int, airborne: bool) -> Dictionary:
	f.buf.tick()
	for sym in _Moves.events(raw, f.raw_prev, f.facing):
		f.buf.push(sym)
	f.raw_prev = raw
	return _Moves.match_special(f.buf, airborne)


func _think(f: Fight, other: Fight, raw: int) -> void:
	var airborne := (f.yi() + BOX_H) < FLOOR_Y

	# Face the opponent whenever both feet are down. The engine does this in
	# t_walk_flip_check, which is not decompiled; this is the obvious rule and
	# is a stand-in.
	if not airborne and f.st != St.ATTACK and f.st != St.HIT:
		f.facing = 1 if other.xi() >= f.xi() else -1

	var dir_f := IN_RIGHT if f.facing > 0 else IN_LEFT
	var dir_b := IN_LEFT if f.facing > 0 else IN_RIGHT

	if f.timer > 0:
		f.timer -= 1

	var vx := 0
	match f.st:
		St.HIT:
			if f.timer == 0:
				f.st = St.STANCE
				f.table = BT_STANCE
			return
		St.ATTACK:
			if f.timer == 0:
				f.st = St.JUMP if airborne else St.STANCE
				f.table = BT_JUMP if airborne else BT_STANCE
				f.move = MV_NONE
			return
		St.SPECIAL:
			if f.timer == 0:
				f.st = St.STANCE
				f.table = BT_STANCE
				f.special = 0
				f.special_name = ""
			return
		St.JUMP:
			# A jump keeps whatever horizontal velocity it started with and
			# only gravity acts.
			if not airborne:
				f.vy = 0
				f.g = 0
				f.vx = 0
				f.y = (FLOOR_Y - BOX_H) * ONE
				f.st = St.STANCE
				f.table = BT_STANCE
				if audio:
					audio.land()
			else:
				var b := _pressed_button(f, raw)
				if b >= 0 and f.table[b]:
					_start_attack(f, f.table[b])
			return

	# On the ground and free to act. **The special is asked first**: its last
	# symbol is a button, and letting the ordinary button table see it turns
	# every spear into a low punch.
	var sp := _special_asked(f, raw, airborne)
	if not sp.is_empty() and int(sp["ani"]) >= 0:
		f.st = St.SPECIAL
		f.special = int(sp["id"])
		f.special_name = str(sp["name"])
		f.timer = _ani_length(int(sp["ani"]), maxi(1, RATE_STANCE + rate_bias))
		f.timer_total = f.timer
		f.table = BT_NULL
		f.connected = false
		f.buf.clear()
		f.vx = 0
		if audio:
			audio.voice()
		return

	var btn := _pressed_button(f, raw)

	if raw & IN_DOWN:
		f.st = St.DUCK
		f.table = BT_DUCK
	elif raw & IN_UP:
		# **The jump is one negative vy against one positive gravity.** That is
		# the whole arc, plus gravity_n_bounds' single add.
		f.vy = JUMP_VY
		f.g = GRAVITY
		if raw & dir_f:
			f.vx = JUMP_VX * f.facing
		elif raw & dir_b:
			f.vx = -JUMP_VX * f.facing
		else:
			f.vx = 0
		f.st = St.JUMP
		# Straight up and angled are DIFFERENT TABLES -- which is why the
		# engine ships both bt_jump and bt_angle_jump.
		f.table = BT_ANGLE_JUMP if (raw & (dir_f | dir_b)) else BT_JUMP
		return
	elif raw & dir_f:
		f.st = St.WALK_F
		f.table = BT_STANCE
		vx = WALK_FORWARD[CHARACTER][WALK_SPEED] * f.facing
	elif raw & dir_b:
		f.st = St.WALK_B
		f.table = BT_STANCE
		vx = -WALK_BACKWARD[CHARACTER][WALK_SPEED] * f.facing
	else:
		f.st = St.STANCE
		f.table = BT_STANCE

	if btn >= 0 and f.table[btn]:
		var mv: int = f.table[btn]
		if mv == MV_BLOCK or mv == MV_DUCK_BLOCK:
			f.st = St.BLOCK
			f.timer = 2
			f.timer_total = 2
			vx = 0
		else:
			_start_attack(f, mv)
			vx = 0
	f.vx = vx


func _resolve_hits(a: Fight, b: Fight) -> void:
	# A special connects too. **Its reach and damage are chosen**: the spear is
	# a projectile in the real game and the teleport moves the fighter behind
	# his opponent, and neither is implemented. What is implemented is the
	# input, the animation, and that it lands.
	if a.st == St.SPECIAL:
		if a.connected:
			return
		@warning_ignore("integer_division")
		var half := a.timer_total / 2
		if a.timer == half and absi(b.xi() - a.xi()) < REACH_KICK * 2:
			a.connected = true
			b.health -= DAMAGE * 2
			b.st = St.HIT
			b.timer = _ani_length(ANI_HIT, maxi(1, RATE_STANCE + rate_bias))
			b.timer_total = b.timer
			b.table = BT_NULL
			b.vx = KNOCKBACK * 2 * (1 if b.xi() > a.xi() else -1)
			b.buf.clear()
			if audio:
				audio.hit(true, true)
		return
	if a.st != St.ATTACK or a.connected:
		return
	# The strike lands in the middle of the move, not at its start.
	@warning_ignore("integer_division")
	if a.timer != _move_frames(a.move) / 2:
		return

	var reach := _move_reach(a.move)
	var dx := b.xi() - a.xi()
	var dy := b.yi() - a.yi()

	# A move only reaches FORWARD, so the test flips with the facing.
	if a.facing > 0:
		if dx < 0 or dx > reach:
			return
	elif dx > 0 or -dx > reach:
		return
	if dy < -BOX_H or dy > BOX_H:
		return

	a.connected = true
	# The reaction: pushed away from whoever hit him, facing kept.
	b.vx = KNOCKBACK * (1 if dx > 0 else -1)
	b.buf.clear()
	if b.st == St.BLOCK:
		b.health -= 1                      # chip
		if audio:
			audio.block()
	else:
		b.health -= DAMAGE
		b.st = St.HIT
		# **As long as the reaction animation, not a number.** The engine leaves
		# a reaction when its stream ends; a fixed count is what made a hit feel
		# detached from what was on screen.
		var hit_ani: int = ANI_DUCK_HIT if b.table == BT_DUCK else ANI_HIT
		b.timer = _ani_length(hit_ani, maxi(1, RATE_STANCE + rate_bias))
		b.timer_total = b.timer
		b.table = BT_NULL                  # how the engine takes input away
		if audio:
			audio.hit(a.move == MV_UPPERCUT,
				a.move == MV_HI_PUNCH or a.move == MV_HI_KICK)
	if b.health <= 0:
		b.health = 0
		a.wins += 1
		if audio:
			audio.voice()


## One 60 Hz frame.
func tick() -> void:
	var raw := [_read_player(0), _read_player(1)]
	last_raw = raw[0]
	last_special = ""
	if fighters[0].st == St.SPECIAL and fighters[0].timer == fighters[0].timer_total:
		last_special = fighters[0].special_name

	for i in 2:
		_think(fighters[i], fighters[1 - i], raw[i])

	# **The animation clock runs on the GAME's tick**, not on the renderer's,
	# and it runs for every state rather than only the walk. Which animation is
	# playing follows the state; starting the one already playing is a no-op,
	# so a held button does not restart the cycle every frame.
	for f in fighters:
		var pick := _ani_for(f)
		var want: int = pick[1]
		if want > 0:
			want = maxi(1, want + rate_bias)
		f.set_ani(pick[0], want)
		var s := _stream(f.ani)
		if s.is_empty():
			continue
		var n: int = (s[2] as Array).size()
		if not f.tick_ani(n, s[1]):
			continue
		if audio and (f.st == St.WALK_F or f.st == St.WALK_B):
			# Two footfalls in the cycle. WHICH frames they land on is a choice:
			# the clip names them SCWALK1..9 and nothing marks contact.
			@warning_ignore("integer_division")
			var half := n / 2
			if f.ani_index == 0 or f.ani_index == half:
				audio.step()
	_resolve_hits(fighters[0], fighters[1])
	_resolve_hits(fighters[1], fighters[0])

	for f in fighters:
		# **gravity_n_bounds, transcribed**: gravity adds into vy, and x is
		# clamped against G[0xb0] + 0x3a and G[0xb4] + 0x15f. In the C build
		# this line calls the decompiled function itself; here it is a reading
		# of it.
		f.vy += f.g

		# DisplayUpdate's two integrations, the other half of the same physics.
		f.x += f.vx
		f.y += f.vy

		if f.xi() < WALL_L:
			f.x = WALL_L * ONE
		elif f.xi() > WALL_R:
			f.x = WALL_R * ONE

		# The floor. gravity_n_bounds knows about walls, not about the ground;
		# the engine grounds a fighter in code that has not been read.
		if f.yi() + BOX_H > FLOOR_Y:
			f.y = (FLOOR_Y - BOX_H) * ONE
			if f.vy > 0:
				f.vy = 0

	if fighters[0].health == 0 or fighters[1].health == 0:
		frame += 1
		if frame > 180:
			reset()
	frame += 1


# -------------------------------------------------------------------- drawing
## Which of the engine's animations this fighter is showing, and at what rate.
##
## **A rate of -1 means INHERIT**, which is what every state that does not call
## `init_anirate` does. See RATE_STANCE.
func _ani_for(f: Fight) -> Array:
	match f.st:
		St.SPECIAL:
			for s in _Moves.SPECIALS:
				if int(s["id"]) == f.special:
					return [int(s["ani"]), -1]
			return [ANI_STANCE, -1]
		St.ATTACK:
			return [MOVE_ANI[f.move], -1]
		St.HIT:
			return [ANI_DUCK_HIT if f.table == BT_DUCK else ANI_HIT, -1]
		St.BLOCK:
			return [ANI_BLOCK, -1]
		St.DUCK:
			return [ANI_DUCK, -1]
		St.JUMP:
			return [ANI_JUMPFLIP if f.table == BT_ANGLE_JUMP else ANI_JUMP, -1]
		St.WALK_F:
			return [ANI_WALK_F, WALK_FORWARD[CHARACTER][WALK_RATE]]
		St.WALK_B:
			return [ANI_WALK_B, WALK_BACKWARD[CHARACTER][WALK_RATE]]
	if f.health == 0:
		return [ANI_VICTORY, -1]
	# Standing is the one that sets it, and everything else lives off that.
	return [ANI_STANCE, RATE_STANCE]


## One animation's [name, loops, frames], or an empty one.
static func _stream(id: int) -> Array:
	if id < 0 or id >= _Ani.ANI.size():
		return []
	return _Ani.ANI[id]


## How many game frames an animation takes end to end. **This is what a move
## lasts**: its own length, so nothing is ever cut off part way.
func _ani_length(id: int, rate: int) -> int:
	var s := _stream(id)
	if s.is_empty():
		return rate
	return (s[2] as Array).size() * rate


func _pose(f: Fight) -> void:
	var s := _stream(f.ani)
	if s.is_empty():
		return
	var frames: Array = s[2]
	var n := frames.size()
	var idx: int = clampi(f.ani_index, 0, n - 1)
	var nxt: int = idx + 1
	if nxt >= n:
		# A one-shot holds its last frame; a loop goes round. Interpolating a
		# held frame against itself is what keeps it still rather than drifting.
		nxt = 0 if s[1] else idx
	var frac := 1.0 - float(f.ani_count) / float(maxi(f.ani_rate, 1))
	f.node.set_pose(frames[idx], frames[nxt], frac)


func _scene_x(f: Fight) -> float:
	return float(f.xi()) * scale_units


func _scene_y(f: Fight) -> float:
	# The engine's y is the TOP of the box and grows DOWNWARD, so the height
	# above the floor is the floor minus where the feet are.
	#
	# No correction for where the model's feet sit: the skinned character's
	# lowest vertex is at -3.9 and Graveyard's cobbles are a plane at exactly
	# y = 0, so the model already stands on the floor at the origin.
	return float(FLOOR_Y - (f.yi() + BOX_H)) * scale_units


func _place() -> void:
	for f in fighters:
		if not frozen:
			_pose(f)
		f.node.position = Vector3(_scene_x(f), _scene_y(f), 0.0)
		f.node.set_facing(f.facing)


## demo.c's framing: a LEVEL camera -- no pitch, because tilting it down is
## what makes a render look like a model viewer instead of a match -- at a
## distance off the fighter's own height, eye two thirds of the way up, widened
## when the two separate so both stay in frame. That widening is what the
## engine's own camera limits at G + 0x468 and G + 0x470 are for.
func _frame_camera() -> void:
	if _cam == null:
		return
	var mid := (_scene_x(fighters[0]) + _scene_x(fighters[1])) * 0.5
	var sep := absf(_scene_x(fighters[0]) - _scene_x(fighters[1]))

	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	# To fit a horizontal span S at this field of view:
	#     S/2 <= dist * tan(fov/2) * aspect
	# The span has to include the two BODIES, not just the gap between their
	# centres, or a fighter at the edge is cut in half.
	var span := sep + 2.2 * width
	var need := span / (2.0 * 0.2217 * aspect)
	var dist := maxf(height * 4.48, need)

	_cam.position = Vector3(mid, height * 0.66, dist)
	_cam.rotation = Vector3.ZERO
	_cam.near = height * 0.15
	_cam.far = maxf(_cam.far, dist * 4.0)


func _process(dt: float) -> void:
	if fighters.size() < 2:
		return
	# Placing and framing happen even when the fight is not ticking: a frozen
	# pose still has to stand in the right place and be looked at from the
	# right distance. Leaving those inside the `enabled` guard left `--pose`
	# renders framed by the stage viewer's camera, a third of a mile away.
	if not enabled:
		_place()
		_frame_camera()
		return
	_now += dt
	# A fixed 60 Hz with an accumulator, and a cap so a long stall catches up
	# over a few frames instead of simulating a thousand at once.
	_accum += dt
	var n := 0
	var step := 1.0 / (TICK_HZ * maxf(game_speed, 0.05))
	while _accum >= step and n < MAX_CATCHUP:
		_accum -= step
		tick()
		n += 1
	if n == MAX_CATCHUP:
		_accum = 0.0
	_place()
	_frame_camera()
	_draw_boxes()


## The hitboxes, as wire boxes in the world.
##
## Rebuilt from the same numbers the hit test uses, every frame, rather than
## from anything the renderer knows: a debug box drawn from a second source can
## agree with the screen and disagree with the fight, which is the one thing it
## must not do.
func _draw_boxes() -> void:
	if not show_hitbox:
		for b in _boxes:
			b.visible = false
		return
	while _boxes.size() < fighters.size() * 2:
		var mi := MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.no_depth_test = true
		mi.material_override = mat
		add_child(mi)
		_boxes.append(mi)

	for i in fighters.size():
		var f := fighters[i]
		# The engine's y is the TOP of the box and grows DOWNWARD, so the box
		# hangs from `y` toward the floor.
		var x := float(f.xi() + BOX_LEFT) * scale_units
		var top := float(FLOOR_Y - f.yi() - BOX_TOP) * scale_units
		var bot := top - float(BOX_H) * scale_units
		var w := float(BOX_W) * scale_units
		_boxes[i * 2].mesh = _wire_box(x, bot, x + w, top,
			Color(0.2, 1.0, 0.3) if f.st != St.HIT else Color(1.0, 0.3, 0.2))
		_boxes[i * 2].visible = true

		# The reach of an attack in flight, so a chosen number is visible as
		# one. Nothing is drawn when the fighter is not attacking.
		var r := _boxes[i * 2 + 1]
		if f.st != St.ATTACK:
			r.visible = false
			continue
		var reach := float(_move_reach(f.move)) * scale_units
		var cx := float(f.xi()) * scale_units
		var mid := top - float(BOX_H) * scale_units * 0.45
		var x0: float = cx if f.facing > 0 else cx - reach
		r.mesh = _wire_box(x0, mid - 4.0, x0 + reach, mid + 4.0,
			Color(1.0, 0.9, 0.2))
		r.visible = true


## A rectangle in the XY plane, as lines.
func _wire_box(x0: float, y0: float, x1: float, y1: float,
			   col: Color) -> ArrayMesh:
	var v := PackedVector3Array([
		Vector3(x0, y0, 0), Vector3(x1, y0, 0),
		Vector3(x1, y0, 0), Vector3(x1, y1, 0),
		Vector3(x1, y1, 0), Vector3(x0, y1, 0),
		Vector3(x0, y1, 0), Vector3(x0, y0, 0)])
	var c := PackedColorArray()
	c.resize(v.size())
	c.fill(col)
	var arrays := []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = v
	arrays[ArrayMesh.ARRAY_COLOR] = c
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return am


## One line per fighter, for the HUD.
func status() -> String:
	var names := ["STANCE", "WALK-F", "WALK-B", "DUCK", "BLOCK", "JUMP",
		"ATTACK", "HIT", "SPECIAL"]
	var out := "%d fps   pose %.1f ms   tick %d
" % [
		Engine.get_frames_per_second(),
		(fighters[0].node.pose_usec + fighters[1].node.pose_usec) / 1000.0,
		frame]
	for i in fighters.size():
		var f := fighters[i]
		out += "P%d %3d hp  %-7s %-11s  x %5d  y %5d  %s\n" % [
			i + 1, f.health, names[f.st],
			f.special_name if f.st == St.SPECIAL else (
				MOVE_NAME[f.move] if f.st == St.ATTACK else ""),
			f.xi(), f.yi(), "->" if f.facing > 0 else "<-"]
	return out
