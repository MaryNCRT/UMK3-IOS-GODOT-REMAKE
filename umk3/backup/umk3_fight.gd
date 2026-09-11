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

## mk3_getbbox's hard-coded animation: 56 wide and 72 tall.
const BOX_W := 56
const BOX_H := 72

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

const WALK_VX := int(4.0 * ONE)         ## forward walk, units per frame
const WALK_BACK_VX := int(3.0 * ONE)    ## backing up is slower
const JUMP_VY := int(-10.0 * ONE)       ## one negative vy ...
const GRAVITY := int(0.40 * ONE)        ## ... against one positive g
const JUMP_VX := int(6.0 * ONE)         ## an angled jump's horizontal speed

## **How long a move lasts is the CLIP's length**, not a number picked here:
## the frame list says SCHIPUNCH is seven frames. What is chosen is only the
## tempo -- how many 60 Hz frames one animation frame is held for. Two is 30 Hz.
const ANIM_HOLD := 2
const IDLE_HZ := 12.0
const T_HIT := 16
## The walk advances with DISTANCE, which is what keeps the feet from skating.
const WALK_STRIDE := 8
const REACH_PUNCH := 70
const REACH_KICK := 86
const DAMAGE := 4
const START_GAP := 55

## The engine runs at a fixed rate and so does this: every duration in the
## fight is counted in FRAMES. Tying the tick to the display made every speed
## in the game three or four times too fast on a machine with vsync off.
const TICK_HZ := 60.0
const MAX_CATCHUP := 4

# ==================================================== Scorpion's clips
#
# Every one is a real clip name and a real frame range out of
# `res/framelists/scorpionframes.txt`. A `.skinanim` is one long stream holding
# every animation the character has, so a range only means something because
# the frame list names each frame.

const CL_STANCE := [216, 224]
const CL_WALK := [282, 290]
const CL_DUCK := [20, 22]
const CL_BLOCK := [1, 3]
const CL_JUMP := [94, 96]
const CL_JUMPFLIP := [97, 104]
const CL_HIT := [71, 73]
const CL_DUCKHIT := [30, 32]
const CL_VICTORY := [276, 281]

const CL_MOVE := [
	[0, 0],          # MV_NONE
	[80, 86],        # SCHIPUNCH
	[136, 141],      # SCLOPUNCH
	[1, 3],          # SCBLOCK
	[74, 79],        # SCHIKICK
	[130, 135],      # SCLOKICK
	[271, 275],      # SCUPPERCUT
	[36, 38],        # SCDUCKPUNCH
	[23, 25],        # SCDUCKBLOCK
	[26, 29],        # SCDUCKHIKICK
	[33, 35],        # SCDUCKLOKICK
	# There is no SCJUMPPUNCH in the frame list. The flip punch is the one
	# airborne punch Scorpion has and stands in for both -- a substitution, and
	# said out loud rather than hidden.
	[62, 64],        # SCFLIPUNCH   as jump punch
	[105, 107],      # SCJUMPKICK
	[62, 64],        # SCFLIPUNCH
	[54, 56],        # SCFLIPKICK
]

enum St { STANCE, WALK_F, WALK_B, DUCK, BLOCK, JUMP, ATTACK, HIT }

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
	var anim_t := 0.0
	var anim_last := -1
	var node = null

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

## A scripted ten-bit word, replacing the keyboard for one player. `--drive`
## sets it, and it exists so that walking, jumping and punching can be SEEN in
## a screenshot rather than asserted -- there is no way to claim input works
## without watching something move.
var forced := [-1, -1]

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

	# The stance and the walk are every round's first two seconds.
	var warm := []
	for k in range(CL_STANCE[0], CL_STANCE[1] + 1):
		warm.append(k)
	for k in range(CL_WALK[0], CL_WALK[1] + 1):
		warm.append(k)
	fighters[0].node.prewarm(warm)

	# **The scale is derived from the character, not picked.** The engine says
	# a fighter is 72 units tall; the model says how tall it is in scene units.
	# One number joins a two-dimensional engine world to a 3D stage.
	height = fighters[0].node.height
	width = fighters[0].node.width
	depth = fighters[0].node.depth
	# **Height, not width.** The two ratios disagree by 39 per cent, because
	# `mk3_getbbox`'s hard-coded 56 x 72 is a HITBOX for one animation and not
	# the model's outline. The height is the one both systems describe the same
	# way: the engine's floor is at 547 and a fighter's head is 72 above it.
	scale_units = height / float(BOX_H)
	reset()
	return true


func reset() -> void:
	for i in fighters.size():
		var f := fighters[i]
		# The arena is 1,394 units wide and a fighter is 56 across, so starting
		# at the walls would put twenty-four body widths between them.
		@warning_ignore("integer_division")
		var mid := (WALL_L + WALL_R) / 2
		f.x = (mid + (START_GAP if i == 1 else -START_GAP)) * ONE
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
		f.anim_t = 0.0
		f.anim_last = -1
	frame = 0


# --------------------------------------------------------------------- input
func _read_player(which: int) -> int:
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
	if mv <= MV_NONE or mv >= CL_MOVE.size():
		return ANIM_HOLD
	var c: Array = CL_MOVE[mv]
	return (c[1] - c[0] + 1) * ANIM_HOLD


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

	# On the ground and free to act.
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
		vx = WALK_VX * f.facing
	elif raw & dir_b:
		f.st = St.WALK_B
		f.table = BT_STANCE
		vx = -WALK_BACK_VX * f.facing
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
	if b.st == St.BLOCK:
		b.health -= 1                      # chip
		if audio:
			audio.block()
	else:
		b.health -= DAMAGE
		b.st = St.HIT
		b.timer = T_HIT
		b.timer_total = T_HIT
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

	for i in 2:
		_think(fighters[i], fighters[1 - i], raw[i])
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
func _clip_for(f: Fight) -> Array:
	match f.st:
		St.ATTACK:
			return [CL_MOVE[f.move], false]
		St.HIT:
			return [CL_DUCKHIT if f.table == BT_DUCK else CL_HIT, false]
		St.BLOCK:
			return [CL_BLOCK, false]
		St.DUCK:
			return [CL_DUCK, false]
		St.JUMP:
			return [CL_JUMPFLIP if f.table == BT_ANGLE_JUMP else CL_JUMP, false]
		St.WALK_F, St.WALK_B:
			return [CL_WALK, true]        # driven by distance, not by a clock
	if f.health == 0:
		return [CL_VICTORY, false]
	return [CL_STANCE, true]


func _pose(f: Fight) -> void:
	var r := _clip_for(f)
	var c: Array = r[0]
	var loop: bool = r[1]
	var from: int = c[0]
	var to: int = c[1]
	var span: int = maxi(to - from + 1, 1)

	if f.st == St.WALK_F or f.st == St.WALK_B:
		# **The walk is driven by distance, not by the clock.** `anim_t` counts
		# animation frames and advances by however far the fighter actually
		# moved, so the contact foot stays planted at any speed.
		f.anim_t += absf(float(f.vx) / float(ONE)) / float(WALK_STRIDE)
		var pos := fmod(f.anim_t, float(span))
		var idx := int(pos)
		# Two footfalls in a nine-frame cycle. WHICH frames they are on is a
		# choice: the clip names them SCWALK1..9 and nothing marks contact.
		@warning_ignore("integer_division")
		var half := span / 2
		if idx != f.anim_last and audio and (idx == 0 or idx == half):
			audio.step()
		f.anim_last = idx
		f.node.set_pose(from + idx, from + ((idx + 1) % span), pos - floorf(pos))
		return
	f.anim_last = -1

	if loop:
		var pos := _now * IDLE_HZ
		var fa := from + int(fmod(pos, float(span)))
		var fb := from + int(fmod(pos + 1.0, float(span)))
		f.node.set_pose(fa, fb, float(pos - floorf(pos)))
		return

	# A one-shot clip plays across the state's own timer, so a punch that lasts
	# fourteen frames shows its whole animation in fourteen.
	var total := f.timer_total if f.timer_total > 0 else 1
	var done := maxi(total - f.timer, 0)
	var p := minf(float(done) * float(span) / float(total), float(span - 1))
	var a := from + int(p)
	f.node.set_pose(a, mini(a + 1, to), p - floorf(p))


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
	while _accum >= 1.0 / TICK_HZ and n < MAX_CATCHUP:
		_accum -= 1.0 / TICK_HZ
		tick()
		n += 1
	if n == MAX_CATCHUP:
		_accum = 0.0
	_place()
	_frame_camera()


## One line per fighter, for the HUD.
func status() -> String:
	var names := ["STANCE", "WALK-F", "WALK-B", "DUCK", "BLOCK", "JUMP",
		"ATTACK", "HIT"]
	var out := ""
	for i in fighters.size():
		var f := fighters[i]
		out += "P%d %3d hp  %-7s %-11s  x %5d  y %5d  %s\n" % [
			i + 1, f.health, names[f.st],
			MOVE_NAME[f.move] if f.st == St.ATTACK else "",
			f.xi(), f.yi(), "->" if f.facing > 0 else "<-"]
	return out
