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
const _Spear := preload("res://umk3/umk3_spear.gd")
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

## **The attack boxes and the damage, measured.**
##
## `punch_strike_check` -> `strike_check_a0` -> `strike_check_a0_core` calls
## `get_char_stk` (0x00055f88), which indexes a global at 0x000f3170 by the
## CHARACTER NUMBER and then by a strike id, and hands the record to
## `strike_check_ptr` (0x00059424). That walks four int32 out of it into the
## object's 0x20, 0x24, 0x28 and 0x2c before calling `strike_check_regs`.
##
## The records have symbols on them. Scorpion is a ninja, so his are the
## `_stk_nj_*` set plus two of his own, `_stk_scorp_spear` and `_stk_scorp_tele`
## -- seven int32 each, and the first four are a BOX:
##
##     x, y, width, height     relative to the fighter, y growing DOWNWARD
##
## and the fifth word's high byte is the DAMAGE. Nothing about that reading is
## assumed: the uppercut's box is the only one with a negative y (-19) and the
## tallest height (74), the sweep's is the lowest (y 107) and the flattest (27),
## and the damage runs jab 11, low punch 8, low kick 21, high kick 24,
## roundhouse 29, uppercut 36. That is Mortal Kombat's own damage order, from a
## table nobody here wrote.
##
## The seventh word is 1 for everything except the sweep, which is 2 -- a low
## attack, which is what a sweep is.
##
## This replaces REACH_PUNCH = 70 and REACH_KICK = 86 and DAMAGE = 4, all three
## invented, and a hit test that compared distances instead of boxes.
const STK_X := 0
const STK_Y := 1
const STK_W := 2
const STK_H := 3
const STK_DMG := 4
const STK_LEVEL := 5

const STRIKE := {
	MV_HI_PUNCH:   [77, 1, 53, 33, 11, 1],       # _stk_nj_hi_punch
	MV_LO_PUNCH:   [84, 31, 61, 20, 8, 1],       # _stk_nj_lo_punch
	MV_HI_KICK:    [96, 4, 65, 44, 24, 1],       # _stk_nj_hikick
	MV_LO_KICK:    [109, 42, 74, 19, 21, 1],     # _stk_nj_lokick
	MV_UPPERCUT:   [77, -19, 58, 74, 36, 1],     # _stk_nj_uppercut
	MV_DUCK_PUNCH: [77, 54, 54, 18, 6, 1],       # _stk_nj_duck_punch
	MV_DUCK_KICKH: [72, 59, 65, 30, 12, 1],      # _stk_nj_duck_kickh
	MV_DUCK_KICKL: [87, 105, 68, 22, 6, 1],      # _stk_nj_duck_kickl
	MV_JUMP_PUNCH: [78, 23, 58, 46, 16, 1],      # _stk_nj_jump_punch
	MV_JUMP_KICK:  [78, 2, 66, 59, 19, 1],       # _stk_nj_jump_kick
	MV_FLIP_PUNCH: [78, 23, 58, 46, 16, 1],      # _stk_nj_flip_punch
	MV_FLIP_KICK:  [66, 35, 46, 38, 26, 1],      # _stk_nj_flip_kick
}

## The two Scorpion has of his own.
const STK_SPEAR := [0, 0, 22, 22, 8, 1]          # _stk_scorp_spear
const STK_TELE := [76, 17, 54, 42, 15, 1]        # _stk_scorp_tele


# ================================================ the two specials, MEASURED
#
# Both were animations with nothing behind them. Both are now numbers out of
# the binary, and the path to each is written down so it can be checked.

## **The spear.** `t_do_scorpion_spear` (0x000515bc) writes 36 into the
## object's 0x1c and jumps to `t_do_zap` (0x000758bc), which indexes
## `_projectile_jumps` (0x00172694) with it -- and entry 36 of that table is
## `tl_do_scorpion_spear`. That hands to `t_new_scorpion_spear_proc`, which
## zeroes 0x1c and 0x20, and then to **`t_new_spear_proc` (0x0007c830)**, where
## the projectile is actually born:
##
##     obj->0x20 += 0x18        then multi_adjust_xy -- so the spear appears
##                              0 in front of the fighter and 24 BELOW his y,
##                              which is his chest
##     obj->0x40 = 9            the projectile's own animation
##     obj->0x20 = 0xfff        init_anirate's "never advance" sentinel: the
##                              spear does not animate, which is why the rope
##                              is cycled by the RENDERER instead
##     obj->0x1c = 0xa0000      10.0 in 16.16
##     set_proj_vel (0x00075d6c) negates that for a fighter facing left and
##                              writes it into the part's x velocity
##
## So: **ten units a frame, dead level, from chest height, no gravity.**
const SPEAR_DY := 24                     ## measured, t_new_spear_proc
const SPEAR_VX := int(10.0 * ONE)        ## measured, 0xa0000

## **The teleport punch is not a warp.** `t_do_scorp_tele` (0x00050c5c) writes
## 22 into 0x1c and jumps to `t_do_body_propell`, which indexes
## `_propell_table` (0x00166f4c) -- twenty-nine function pointers, not numbers
## -- and entry 22 is `tl_do_scorp_tele` (0x0004093c). That one calls
## `face_opponent`, `flip_multi` and **`set_noedge`**, and then sets
##
##     obj->0x1c = 0xa0000              10.0      forward
##     obj->0x20 = 0xa0000 - 0xd0000   -3.0       upward
##     obj->0x24 = that + 0x35000       0.3125    gravity
##
## which is a jump: three up against 0.3125 down is 9.6 frames to the apex and
## about 19 in the air, carrying him 192 units -- well past an opponent who
## starts 110 away. `set_noedge` is why he may leave the arena on the way.
## That is the move: he dives forward through the opponent and lands behind
## him, and `_stk_scorp_tele` is the punch that lands with him.
const TELE_VX := int(10.0 * ONE)         ## measured, 0xa0000
const TELE_VY := -int(3.0 * ONE)         ## measured, 0xa0000 - 0xd0000
const TELE_G := 0x5000                   ## measured, 0.3125

## Which frame of the spear animation lets go of it.
##
## **Chosen.** `SCSPEAR` is four frames and the engine starts the projectile
## from a state the animation does not describe. One in is where the arm is
## out.
const SPEAR_THROW_FRAME := 1

## Reeling the victim in. `t_scorp_rope_pull` (0x0007c5fc) is the puller's side
## and `t_tugged_in_by_spear` (0x0007c504) the victim's; the two rates they set
## -- 3 and 8 -- are measured, the SPEED is not: the pull is a transfer between
## two threads and the velocity comes from code that is not decompiled. Ten a
## frame is the rope going back in as fast as it came out, and it stops where
## `t_joy_hi_punch` stops calling itself far away, at 0x40 -- 64 units.
const PULL_VX := int(10.0 * ONE)         ## chosen -- the rope's own speed
const PULL_STOP := 64                    ## measured, t_joy_hi_punch's 0x40
const RATE_PULL := 3                     ## measured, t_scorp_rope_pull
const RATE_TUGGED := 8                   ## measured, t_tugged_in_by_spear

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


## **SPEARED is a state, not a hit.** The engine gives the victim his own
## thread -- `t_tugged_in_by_spear` -- rather than a reaction, because being
## dragged across the floor is something that happens over many frames and a
## reaction is over when its animation is.
enum St { STANCE, WALK_F, WALK_B, DUCK, BLOCK, JUMP, ATTACK, HIT, SPECIAL,
	SPEARED }

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

	## **His spear, while it is out.** One per fighter, because that is what
	## `_SpearStartPos[2]` and `_DrawSpear[2]` are: two players, one each.
	var sp_live := false
	var sp_x := 0                ## 16.16, like every other position
	var sp_y := 0
	var sp_vx := 0
	var sp_thrown := false       ## has this throw let go of it yet
	var sp_tex := 0              ## _SpearWhichTexture: the rope's frame
	var sp_node = null

	## `set_noedge`: the walls do not apply. The teleport sets it.
	var noedge := false
	## The teleport has left the ground, so landing ends it.
	var tele_air := false
	## Whoever's spear is dragging him, while St.SPEARED.
	var pulled_by = null

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
		# One spear per fighter, because that is what `_DrawSpear[2]` and
		# `_SpearStartPos[2]` are.
		var sp = _Spear.new()
		add_child(sp)
		sp.setup(textures)
		f.sp_node = sp
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
		f.sp_live = false
		f.sp_thrown = false
		f.noedge = false
		f.tele_air = false
		f.pulled_by = null
		f.special = 0
		f.special_name = ""
		f.buf.clear()
		if f.sp_node:
			f.sp_node.clear()
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


## The strike record for whatever this fighter is doing, or an empty array.
func _strike_of(f: Fight) -> Array:
	if f.st == St.SPECIAL:
		# **The spear is not here.** `_stk_scorp_spear` belongs to the
		# projectile, which is its own object with its own box -- see
		# `_spear_box`. Putting it on Scorpion gave the throw an invisible
		# 22-unit punch and gave the spear itself nothing.
		if f.special == _Moves.SP_TELEPUNCH:
			return STK_TELE
		return []
	if f.st == St.ATTACK and STRIKE.has(f.move):
		return STRIKE[f.move]
	return []


## Where a strike's box sits in the world, as [x0, y0, x1, y1] in engine units
## with y growing DOWNWARD, which is the engine's own sense.
##
## The record's x is the distance IN FRONT of the fighter, so facing mirrors it
## about his origin rather than negating it -- a box 77 wide starting 77 ahead
## becomes one ending 77 behind.
func _strike_box(f: Fight, stk: Array) -> Array:
	var x0: int
	if f.facing > 0:
		x0 = f.xi() + stk[STK_X]
	else:
		x0 = f.xi() - stk[STK_X] - stk[STK_W]
	var y0: int = f.yi() + stk[STK_Y]
	return [x0, y0, x0 + stk[STK_W], y0 + stk[STK_H]]


## A fighter's own body box, from `_FrameInfo2`. See BOX_W.
func _body_box(f: Fight) -> Array:
	var x0: int = f.xi() + BOX_LEFT
	var y0: int = f.yi() + BOX_TOP
	return [x0, y0, x0 + BOX_W, y0 + BOX_H]


static func _overlap(a: Array, b: Array) -> bool:
	return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


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
	if not airborne and f.st != St.ATTACK and f.st != St.HIT 			and f.st != St.SPEARED:
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
			if f.special == _Moves.SP_SPEAR:
				# The animation lets go of it; from there the projectile is
				# its own object with its own velocity, which is exactly the
				# shape `t_new_spear_proc` has.
				if not f.sp_thrown and f.ani_index >= SPEAR_THROW_FRAME:
					_throw_spear(f)
			elif f.special == _Moves.SP_TELEPUNCH:
				# It ends when he lands, not when the animation runs out: the
				# arc is nineteen frames and the clip is three.
				if airborne:
					f.tele_air = true
				elif f.tele_air:
					f.noedge = false
					f.vx = 0
					f.st = St.STANCE
					f.table = BT_STANCE
					f.special = 0
					f.special_name = ""
					if audio:
						audio.land()
				return
			if f.timer == 0:
				f.st = St.STANCE
				f.table = BT_STANCE
				f.special = 0
				f.special_name = ""
			return
		St.SPEARED:
			# `t_tugged_in_by_spear`: dragged toward whoever threw it, with no
			# input, until he is close enough to be hit.
			var puller = f.pulled_by
			if puller == null or absi(puller.xi() - f.xi()) <= PULL_STOP:
				f.pulled_by = null
				f.vx = 0
				f.st = St.HIT
				f.timer = _ani_length(ANI_HIT,
					maxi(1, RATE_STANCE + rate_bias))
				f.timer_total = f.timer
				f.table = BT_NULL
			else:
				f.vx = PULL_VX * (1 if puller.xi() > f.xi() else -1)
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
		f.sp_thrown = false
		f.tele_air = false
		f.noedge = false
		if f.special == _Moves.SP_TELEPUNCH:
			# tl_do_scorp_tele, in order: face the opponent, then leave the
			# ground with the three numbers it sets. `set_noedge` is the
			# reason he is allowed to go through the wall he lands beyond.
			f.facing = 1 if other.xi() >= f.xi() else -1
			f.vx = TELE_VX * f.facing
			f.vy = TELE_VY
			f.g = TELE_G
			f.noedge = true
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


## Does whatever `a` is doing reach `b` this frame?
##
## **Box against box**, which is what `strike_check_regs` does with the four
## words `strike_check_ptr` hands it. What was here before compared a distance
## against an invented reach and a dy against the whole body height, so a jab
## landed from anywhere in front and an uppercut could not miss.
##
## The strike is live for the middle of the move. **WHICH frames are live is
## still chosen**: the engine calls `punch_strike_check` from the move's own
## state on the frames that state decides, and those states are not decompiled.
func _resolve_hits(a: Fight, b: Fight) -> void:
	if a.connected:
		return
	var stk := _strike_of(a)
	if stk.is_empty():
		return

	# The active window: from a quarter of the way in to three quarters. A
	# choice, and the only one left in this function.
	var elapsed := a.timer_total - a.timer
	if elapsed < a.timer_total / 4 or elapsed > (a.timer_total * 3) / 4:
		return
	if not _overlap(_strike_box(a, stk), _body_box(b)):
		return

	a.connected = true
	var dmg: int = stk[STK_DMG]
	var away := 1 if b.xi() >= a.xi() else -1
	b.buf.clear()

	# A block stops it. **The sweep is level 2 and a standing block does not
	# stop a low attack** -- that is what the seventh word is for.
	var blocked: bool = b.st == St.BLOCK and (
		int(stk[STK_LEVEL]) == 1 or b.table == BT_DUCK)
	if blocked:
		b.health -= 1                        # chip
		b.vx = KNOCKBACK * away
		if audio:
			audio.block()
		return

	b.health -= dmg
	b.st = St.HIT
	# As long as the reaction animation: the engine leaves a reaction when its
	# stream ends.
	var hit_ani: int = ANI_DUCK_HIT if b.table == BT_DUCK else ANI_HIT
	b.timer = _ani_length(hit_ani, maxi(1, RATE_STANCE + rate_bias))
	b.timer_total = b.timer
	b.table = BT_NULL                        # how the engine takes input away
	# Harder hits push further. The engine takes the reaction's velocity from
	# the move; this scales one number by the damage, which is a stand-in.
	b.vx = KNOCKBACK * away * (2 if dmg >= 24 else 1)
	if audio:
		audio.hit(dmg >= 24, stk[STK_Y] < 40)
	if b.health <= 0:
		b.health = 0
		a.wins += 1
		if audio:
			audio.voice()


## Let go of the spear. `t_new_spear_proc`, transcribed.
func _throw_spear(f: Fight) -> void:
	f.sp_thrown = true
	f.sp_live = true
	f.sp_x = f.x
	f.sp_y = f.y + SPEAR_DY * ONE
	f.sp_vx = SPEAR_VX * f.facing
	f.sp_tex = 0
	if audio:
		audio.swing(false)


## The spear's box, in the same [x0, y0, x1, y1] the body boxes use.
##
## `_stk_scorp_spear` is 0, 0, 22, 22 -- and unlike every other strike record
## those four are relative to the PROJECTILE, which is its own object, so the
## box simply sits on it.
func _spear_box(f: Fight) -> Array:
	var x0: int = f.sp_x >> FX
	var y0: int = f.sp_y >> FX
	return [x0, y0, x0 + STK_SPEAR[STK_W], y0 + STK_SPEAR[STK_H]]


## One frame of a spear in flight.
##
## `t_new_spear_proc`'s state 0x22c is the flying state and it ends two ways:
## the opponent's thread becomes the speared one -- which is this hit -- or the
## projectile stops being valid and the thing flashes out. Leaving the arena is
## this port's version of the second.
func _step_spear(f: Fight, other: Fight) -> void:
	if not f.sp_live:
		return
	f.sp_tex += 1
	f.sp_x += f.sp_vx
	var sx := f.sp_x >> FX
	if sx < WALL_L or sx > WALL_R:
		f.sp_live = false
		return
	if not _overlap(_spear_box(f), _body_box(other)):
		return

	f.sp_live = false
	# A standing block stops it: `_stk_scorp_spear`'s seventh word is 1, a high
	# attack, and that is what a standing block is for.
	if other.st == St.BLOCK:
		other.health -= 1
		if audio:
			audio.block()
		return

	other.health -= STK_SPEAR[STK_DMG]
	other.buf.clear()
	other.table = BT_NULL
	other.st = St.SPEARED
	other.pulled_by = f
	other.vy = 0
	other.g = 0
	other.y = (FLOOR_Y - BOX_H) * ONE       # ground_him
	if audio:
		audio.hit(false, false)
	if other.health <= 0:
		other.health = 0
		f.wins += 1
		other.st = St.HIT
		other.pulled_by = null
		other.timer = _ani_length(ANI_HIT, maxi(1, RATE_STANCE + rate_bias))
		other.timer_total = other.timer


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
	_step_spear(fighters[0], fighters[1])
	_step_spear(fighters[1], fighters[0])

	for f in fighters:
		# **gravity_n_bounds, transcribed**: gravity adds into vy, and x is
		# clamped against G[0xb0] + 0x3a and G[0xb4] + 0x15f. In the C build
		# this line calls the decompiled function itself; here it is a reading
		# of it.
		f.vy += f.g

		# DisplayUpdate's two integrations, the other half of the same physics.
		f.x += f.vx
		f.y += f.vy

		# `set_noedge`: the teleport goes through the wall rather than into it.
		if not f.noedge:
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
		St.SPEARED:
			# `t_tugged_in_by_spear` sets rate 8 -- slow, because he is being
			# dragged rather than reacting.
			return [ANI_HIT, RATE_TUGGED]
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
		_place_spear(f)


## The spear, where the fight says it is.
##
## `RenderExtras` draws the rope from `_SpearStartPos` to `_SpearEndPos`; the
## start is the hand and the end is the head, and both are in world space
## rather than relative to anything. So is this.
func _place_spear(f: Fight) -> void:
	if f.sp_node == null:
		return
	if not f.sp_live:
		f.sp_node.clear()
		return
	var hand_x := float(f.xi()) * scale_units
	var hand_y := float(FLOOR_Y - f.yi() - SPEAR_DY) * scale_units
	var tip_x := float(f.sp_x >> FX) * scale_units
	var tip_y := float(FLOOR_Y - (f.sp_y >> FX)) * scale_units
	f.sp_node.place(hand_x, hand_y, tip_x, tip_y, f.sp_tex, scale_units)


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

		# **The strike's own box**, from the engine's `_stk_*` record, in the
		# same place the hit test puts it. Drawn from `_strike_box` rather than
		# from anything similar, so a box that is drawn and a box that hits
		# cannot drift apart.
		var r := _boxes[i * 2 + 1]
		# A spear in flight IS this fighter's strike, so it is what the strike
		# slot draws while it is out.
		if f.sp_live:
			var pb := _spear_box(f)
			r.mesh = _wire_box(
				float(pb[0]) * scale_units, float(FLOOR_Y - pb[3]) * scale_units,
				float(pb[2]) * scale_units, float(FLOOR_Y - pb[1]) * scale_units,
				Color(1.0, 0.25, 0.2))
			r.visible = true
			continue
		var stk := _strike_of(f)
		if stk.is_empty():
			r.visible = false
			continue
		var sb := _strike_box(f, stk)
		var sx0 := float(sb[0]) * scale_units
		var sx1 := float(sb[2]) * scale_units
		var sy1 := float(FLOOR_Y - sb[1]) * scale_units
		var sy0 := float(FLOOR_Y - sb[3]) * scale_units
		# Yellow while it is winding up, red on the frames it can actually
		# connect -- the same window `_resolve_hits` uses.
		var el := f.timer_total - f.timer
		var live := el >= f.timer_total / 4 and el <= (f.timer_total * 3) / 4
		r.mesh = _wire_box(sx0, sy0, sx1, sy1,
			Color(1.0, 0.25, 0.2) if live and not f.connected
			else Color(0.9, 0.8, 0.25))
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
		"ATTACK", "HIT", "SPECIAL", "SPEARED"]
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
