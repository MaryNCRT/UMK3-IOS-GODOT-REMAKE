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
const _Stk := preload("res://umk3/umk3_strikes.gd")
const _Blood := preload("res://umk3/umk3_blood.gd")

# ============================================================ measured data
#
# Everything in this section came out of the binary. Nothing here is a choice.

## mk3_init_game's defaults, before a level overrides them.
## `mk3_init_game` (0x00031f30) writes RoundParam through the pointer at
## 0x00165670, four words in: **-550, 950, 0, 5.** The ground was 0x12c here
## and it is not in that function -- it is only an origin, so nothing on screen
## moved, but a number that is not the binary's should not sit in this block.
const ROUNDPARAM_LEFT := -550
const ROUNDPARAM_RIGHT := 950
const ROUNDPARAM_GROUND := 0

## `init_players` (0x0005a418), which is where these actually get computed:
##
##     G[0xac] = RoundParam[2] + 0xf7          the floor
##     G[0xb0] = RoundParam[0]                 the camera's leftmost x
##     G[0xb4] = RoundParam[1] - 0x18c - 3     the camera's rightmost x
##
## **0x18c + 3 is 399, and that is the width of the view.** The same 399 turns
## up again in `t_sctele_calla_1` (0x00040aa0), which keeps a teleporting
## fighter inside `G[0x468] .. G[0x468] + 0x18c + 3`. So the camera is a
## 399-unit window that slides between -550 and 950.
const CAM_WIDTH := 0x18c + 3                           #  399

## `gravity_n_bounds`: left = G[0xb0] + 0x3a, right = G[0xb4] + 0x15c + 3.
##
## Which puts the walls **58 units inside the camera's left edge and 48 inside
## its right** -- the arena is smaller than the view, on purpose, so a fighter
## can never reach a screen edge.
const WALL_L := ROUNDPARAM_LEFT + 0x3a                 # -492
const WALL_R := ROUNDPARAM_RIGHT - CAM_WIDTH + 0x15f   #  902

## mk3_update: G[0xac] = RoundParam[2] + 0xf7, every frame.
const FLOOR_Y := ROUNDPARAM_GROUND + 0xf7              #  247

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

## **The angled jump is measured now too, and it was not 6.0.**
##
## `t_do_flip` (0x00030634) does not carry its own horizontal speed: it reads
## whatever the caller left in `obj->field48`, and `plyrthread` is the caller.
## Its two flip entries are the diagonals, selected by a bit PAIR rather than
## by a direction:
##
##     bits & 9 == 9   up+right   0x000314d0  mov.w r3, #0x40000    +4.0
##     bits & 5 == 5   up+left    0x0003126c  ldr   -> 0xfffc0000   -4.0
##
## Same magnitude both ways, so a forward jump and a back jump cover exactly
## the same ground. `t_do_flip` then negates it through `is_he_right`, which
## is what turns the two screen directions into toward/away.
##
## (The port had 6.0 here, which was never read off anything. The decompilation
## briefly had the second literal as -8.0, which was a transcription slip --
## the pc-relative load lands at 0x000317d0 and the word there is 0xfffc0000.)
const JUMP_VX := int(4.0 * ONE)         ## measured, field48 at both flip entries

## **How long a move lasts is its animation's length**, and now that is the
## engine's own stream rather than a range read off the frame list.
const T_HIT := 16

## **The attack boxes and the damage come out of the binary's own table now.**
##
## See umk3_strikes.gd, which is generated from `_nj_strikes` (0x00169f50) and
## carries the reading of `strike_check_regs` that says how the four words turn
## into a rectangle. The short version, because it was wrong here for a week:
##
##     facing right   left = X + x - w,  right = X + x
##     facing left    left = X - x,      right = X - x + w
##
## **x is the FAR edge and w is measured back toward the fighter.** Every box
## in this file used to start at X + x and run outward, which put all of them a
## full width too far away -- the low kick, 74 wide, claimed to reach X+183
## where the engine stops at X+109. Two fighters could stand inside each
## other's boxes and miss.
const STK_X := _Stk.X
const STK_Y := _Stk.Y
const STK_W := _Stk.W
const STK_H := _Stk.H
const STK_DMG := _Stk.DMG
const STK_LEVEL := _Stk.LEVEL

## MV_* -> the strike id the engine uses for it, before the close-range and
## stick-away substitutions in `_strike_id`.
const MOVE_STRIKE := {
	MV_HI_PUNCH: _Stk.HI_PUNCH,
	MV_LO_PUNCH: _Stk.LO_PUNCH,
	MV_HI_KICK: _Stk.HIKICK,
	MV_LO_KICK: _Stk.LOKICK,
	MV_UPPERCUT: _Stk.UPPERCUT,
	MV_DUCK_PUNCH: _Stk.DUCK_PUNCH,
	MV_DUCK_KICKH: _Stk.DUCK_KICKH,
	MV_DUCK_KICKL: _Stk.DUCK_KICKL,
	MV_JUMP_PUNCH: _Stk.JUMP_PUNCH,
	MV_JUMP_KICK: _Stk.JUMP_KICK,
	MV_FLIP_PUNCH: _Stk.FLIP_PUNCH,
	MV_FLIP_KICK: _Stk.FLIP_KICK,
}

# ================================================ the two specials, MEASURED

## **The spear.** `t_do_scorpion_spear` (0x000515bc) writes 36 into the
## object's 0x1c and jumps to `t_do_zap` (0x000758bc), which indexes
## `_projectile_jumps` (0x00172694) with it -- and entry 36 of that table is
## `tl_do_scorpion_spear`. That hands to `t_new_scorpion_spear_proc`, which
## zeroes 0x1c and 0x20, and then to **`t_new_spear_proc` (0x0007c830)**:
##
##     obj->0x20 += 0x18        then multi_adjust_xy -- 0 in front of the
##                              fighter and 24 BELOW his y, which is his chest
##     obj->0x20 = 0xfff        init_anirate's "never advance" sentinel
##     obj->0x1c = 0xa0000      10.0 in 16.16
##     set_proj_vel (0x00075d6c) negates it for a fighter facing left
const SPEAR_DY := 24                     ## measured, t_new_spear_proc
const SPEAR_VX := int(10.0 * ONE)        ## measured, 0xa0000

## **The teleport punch is not a warp.** `t_do_scorp_tele` (0x00050c5c) writes
## 22 into 0x1c and jumps to `t_do_body_propell`, which indexes
## `_propell_table` (0x00166f4c) -- twenty-nine function POINTERS -- and entry
## 22 is `tl_do_scorp_tele` (0x0004093c). That calls `face_opponent`,
## `flip_multi` and **`set_noedge`**, then sets
##
##     obj->0x1c = 0xa0000              10.0      forward
##     obj->0x20 = 0xa0000 - 0xd0000   -3.0       upward
##     obj->0x24 = that + 0x35000       0.3125    gravity
##
## Three up against 0.3125 down is 9.6 frames to the apex and about 19 in the
## air, carrying him 192 units. `set_noedge` is why he may leave the arena;
## `t_sctele_calla_1` (0x00040aa0) keeps him inside the camera instead.
const TELE_VX := int(10.0 * ONE)         ## measured, 0xa0000
const TELE_VY := -int(3.0 * ONE)         ## measured, 0xa0000 - 0xd0000
const TELE_G := 0x5000                   ## measured, 0.3125
const TELE_RATE := 3                     ## measured, obj->0x28 via t_flight_call

## Which frame of the spear animation lets go of it.
##
## **Chosen.** `SCSPEAR` is four frames and the engine starts the projectile
## from a state the animation does not describe. One in is where the arm is out.
const SPEAR_THROW_FRAME := 1

## **Reeling the victim in, and now every number of it is measured.**
## `t_tugged_in_by_spear` (0x0007c504) is the victim's own thread and it reads
## straight through:
##
##     state 0     obj->0x1c = 0x80000; towards_x_vel       8.0 a frame, toward
##                 set_no_block                             he cannot guard
##     state 0x44f get_x_dist; while > 0x40 keep dragging   stops at 64
##                 then stop_me_player
##                      obj->0x40 = 0x25   -> animation 37, SCSTUNNED
##                      pose_a9_manual
##                      obj->0x1c = 8; init_anirate          rate 8
##                      obj->0x48 = 0x40                     64 frames of it
##     state 0x45f next_anirate, count 0x48 down, and LEAVE EARLY if
##                 obj->0x5c is set -- which is the flag a strike sets
##
## So the spear does not just hurt: it drags you in and leaves you **stunned
## for sixty-four frames, unable to block, and the stun breaks the moment
## anything hits you**. That is the whole point of the move and none of it was
## here -- the victim went into an ordinary reaction and walked away.
const PULL_VX := int(8.0 * ONE)          ## measured, 0x80000 + towards_x_vel
const PULL_STOP := 0x40                  ## measured, t_tugged_in_by_spear
const STUN_FRAMES := 0x40                ## measured, obj->0x48
const RATE_PULL := 3                     ## measured, t_scorp_rope_pull
const RATE_TUGGED := 8                   ## measured, init_anirate after the pull


## How hard a hit pushes the victim back, and for how long.
##
## **Chosen.** The engine sends a struck fighter into a reaction state whose
## velocity comes from the move that hit him, and those live in the per-move
## states that are not decompiled. What IS measured is the shape: a reaction is
## a state with its own animation and no input, and it ends when the animation
## does -- which is why T_HIT is now the hit animation's own length rather than
## a number.
const KNOCKBACK := int(2.5 * ONE)
## Half the gap a round opens with.
##
## **Still chosen, but no longer arbitrary.** `init_players` (0x0005a418) puts
## BOTH fighters at x = 0x12f and leaves `repell_func` to separate them, so the
## file holds no opening distance to read. What it does hold is the scale of a
## fight, and every number in it agrees:
##
##     get_x_dist         centre to centre, no boxes
##     t_knee_check       inside 0x4a (74) a kick becomes a knee
##     t_elbow_check      inside 0x4a a high punch becomes an elbow
##     repell_func        pushes apart under 0x3c (60), leashes over 0x130
##     _stk_nj_lo_punch   the shortest normal reaches X + 84
##     _stk_nj_lokick     the longest reaches X + 109
##
## So a fight happens between roughly 60 and 130 units centre to centre. The
## old 110 a side -- 220 apart -- was outside every one of those: with the box
## corrected, nothing either fighter could throw would have reached, which is
## exactly the "it does not hit him" this was.
##
## 50 a side opens the round at 100: inside a jab's 77 against a body that
## starts 29 units before its centre, outside the 74 that would make it an
## elbow, and well clear of the 60 where `repell_func` starts shoving.
var start_gap := 50

## **Where the feet are: `ground_ochar_ob` (0x0005527c), exactly.**
##
##     part->0x12 = G[0xac] - ochar_ground_offsets[character]
##
## which is FLOOR_Y minus the character's own height. This port grounded the
## fighter at `FLOOR_Y - BOX_H` instead -- the HITBOX's height, 130 against
## Scorpion's real 139 -- so every fighter stood nine units too low and every
## strike box, which is placed at `Y + y`, was nine units off with him.
func _ground_y() -> int:
	return FLOOR_Y - GROUND_OFFSET[CHARACTER]


## `repell_func`'s three numbers, all of them the binary's own.
const NEAR_GAP := 0x3c                   ## 60 -- closer and they are shoved
const FAR_GAP := 0x130                   ## 304 -- further and they are reeled
const PUSH_VEL := 0x30000                ## 3.0 in 16.16

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
const ANI_DUCK_BLOCK := 6                ## SCDUCKBLOCK, `t_do_duck_block`
const ANI_BLOCK := 12
const ANI_VICTORY := 13
const ANI_JUMP := 22
const ANI_JUMPFLIP := 26
const ANI_HIT := 28                      ## SCHIHIT
const ANI_LO_HIT := 29                   ## SCLOHIT -- never used before
const ANI_KNOCKDOWN := 30                ## SCKNOCKDOWN
const ANI_SWEEPFALL := 31                ## SCSWEEPFALL
const ANI_STUMBLE := 32                  ## SCSTUMBLE
const ANI_GETUP := 33                    ## SCGETUP
const ANI_SWEEPUP := 34                  ## SCSWEEPUP
const ANI_STUNNED := 37                  ## SCSTUNNED, loops
const ANI_RUN := 70
const ANI_FALLTHUD := 71                 ## SCFALLTHUD
const ANI_SPEAR := 82

## Which animation each REACTION plays.
##
## `t_r_hi_kick`, `t_r_combo0` and `t_combo1` are the three that set it where a
## scan can see it -- `field40 = 0x1c` then `get_char_ani` -- and 0x1c is 28,
## SCHIHIT. `t_stumble_back_vel` takes 32, `t_dizzy_by_boss` 37, and
## `t_r_pounce`, `t_blast_through_anything` and `t_up_2_ceiling` all take 30,
## SCKNOCKDOWN. The rest set the frame through the reaction driver instead and
## are NOT recovered, so the entries below without a note are this port's
## reading of the clip names -- and the clip names are the game's.
const REACT_ANI := {
	0: ANI_HIT,          # t_r_hi_kick       MEASURED, field40 = 0x1c
	1: ANI_LO_HIT,       # t_r_lo_kick
	2: ANI_HIT,          # t_r_hi_punch      t_combo1/t_r_combo0 measure 28
	3: ANI_LO_HIT,       # t_r_lo_punch
	4: ANI_SWEEPFALL,    # t_r_sweep         a sweep takes the feet away
	5: ANI_HIT,          # t_r_duck_punch
	6: ANI_HIT,          # t_r_duck_kickh
	7: ANI_LO_HIT,       # t_r_duck_kickl
	8: ANI_KNOCKDOWN,    # t_r_uppercut
	9: ANI_HIT,          # t_r_elbow_knee
	10: ANI_HIT,         # t_r_flip_kick
	11: ANI_HIT,         # t_r_flip_punch
	12: ANI_KNOCKDOWN,   # t_r_roundhouse
	45: ANI_SWEEPFALL,   # t_r_slide
	76: ANI_HIT,         # t_r_tusk_elbow
	115: ANI_KNOCKDOWN,  # t_r_scorp_tele
	117: ANI_STUMBLE,    # t_r_scorpion_spear
}

## **Which reactions put a fighter on the floor.** The uppercut, the
## roundhouse, the sweep and the slide -- the four that in Mortal Kombat end
## with you getting up again, and the four whose reactions above are a
## knockdown or a fall rather than a flinch.
const KNOCKS_DOWN := [4, 8, 12, 45, 115]

## **The collapse at the end of a round**, from `t_collapse_on_ground`
## (0x0007d294), which is the whole of what the loser does:
##
##     player_normpal, set_noedge, stop_me_player
##     obj->0x64 = 0x12                 eighteen frames of it
##     field40 = 0x1e  (SCKNOCKDOWN)    find_ani_part2, FIND_LAST_FRAME
##     obj->0x1c = ochar_dead_adjusts[character]; obj->0x20 = 0
##     multi_adjust_xy                  so the shift is in X, not Y
##     shake_n_sound
##
## `find_last_frame` is why the body ends flat rather than mid-tumble, and
## `_ochar_dead_adjusts` (0x00174dbc) is why it does not end standing in its
## own footprint: a body lying down takes up room BEHIND where it stood.
const DEAD_ADJUST := [
	-72, -48, -64, -72, -76, -80, -56, -56, -69, -80, -64, -64, -48,
	-72, -56, -56, -56, -56, -56, -56, -56, -56, -56, -56, -56, -56,
]
const COLLAPSE_HOLD := 0x12              ## measured, obj->0x64

## `_getup_speeds` (0x001671a4) is 0x40004 for every character: four and four,
## packed the way the walk table packs a rate and a speed.
const RATE_GETUP := 4

## **The fall, from `t_fall_on_my_back` (0x00041efc).** Four stores and a
## hand-off, and every number of it is here:
##
##     part->0x24 = 0x8000    0.5      the gravity
##     part->0x1c = 0                  no horizontal speed
##     part->0x28 = 5                  the ANIRATE
##     part->0x20 = 0                  **vy zero -- he is not launched**
##     part->0x40 = 5 + 0x19 = 0x1e    animation 30, SCKNOCKDOWN
##
## then `t_flight` -> `t_flight_call`, which copies 0x20 into the part's vy and
## 0x24 into its gravity, calls `away_x_vel` with the zero, and restores 0x28
## as the anirate through `init_anirate`.
##
## So a knockdown is **not a launch**. Gravity is armed and the velocity is
## zero: the CLIP does the tumbling, at a rate of five. This port was throwing
## the victim upward on an arc derived from the clip's own drawn height, which
## was an invented thing sitting on top of a measured one.
const FALL_G := 0x8000                   ## measured, 0.5 in 16.16
const RATE_FALL := 5                     ## measured, part->0x28

## **The uppercut's launch, from `t_rup3` (0x00045ed4).**
##
## The chain took five functions to walk and this is the leaf of it:
##
##     t_r_uppercut -> t_reaction_start -> t_rst5 -> t_cc_ken_masters
##     -> t_avoid_corner_trap -> (state 0x748) -> t_pit_abort -> t_rup3
##
## and `t_rup3` sets, in order:
##
##     obj->0x1c = 0xe ; create_fx          an effect, id 14
##     obj->0x1c = 0x20000                  2.0, through away_x_vel
##     if RoundParam[2] != 0                a different stage floor -> elsewhere
##     if (int8)RoundParam[0x30] != 0
##          obj->0x20 = -1179648            -18.0     vy
##          obj->0x24 = 0x5800                0.34375 gravity
##     else                                 <- THE DEFAULT
##          obj->0x20 = -786432             -12.0     vy
##          obj->0x24 = that + 0xc6000        0.375   gravity
##     obj->0x28 = 5                          the anirate
##     obj->0x40 = 5 + 0x19 = 30              SCKNOCKDOWN
##     -> t_flight -> t_flight_call
##
## `mk3_init_game` writes `RoundParam[0x30] = 0` and `RoundParam[2] = 0`, so
## **the default is -12.0 against 0.375**: a peak of 192 units, one and a third
## body heights, and sixty-four frames in the air. Against the jump's own -10.0
## and 0.5 -- a hundred units -- an uppercut throws you nearly twice as high
## and keeps you up twice as long, which is what an uppercut is for.
##
## The -18.0 branch is a stage flag nobody sets by default. It is kept here
## because it is real, not because anything reaches it yet.
## **`t_rup3` (0x00045ed4), the uppercut's launch, read whole.**
##
##     pl->0x1c = 0x20000     2.0, and `t_flight_call` hands it to away_x_vel
##     pl->0x20 = 0xffee0000  -18.0, which becomes the part's vy
##     pl->0x24 = 0x5800      0.34375, which becomes the part's gravity
##     pl->0x28 = 5           the anirate the flight restores
##     pl->0x40 = 0x1e        animation 30, SCKNOCKDOWN
##     then it pushes `t_flight`, and on the way back `t_reaction_land`
##
## This port had -12.0 against a gravity of 0.375, which are both wrong and
## wrong in the same direction: the arc was 64 frames instead of 104 and
## barely more than half as high. An uppercut in this game throws you off the
## top of the screen -- 18 squared over twice 0.34375 is 471 units, against a
## fighter 130 tall -- and that is what it is supposed to look like.
const UPCUT_VX := int(2.0 * ONE)         ## measured, 0x20000
const UPCUT_VY := -int(18.0 * ONE)       ## measured, 0xffee0000
const UPCUT_G := 0x5800                  ## measured, 0.34375

## **How fast each reaction throws the victim sideways**, from the leaf that
## arms its flight.
##
## The uppercut's is `obj->0x1c = 0x20000` in `t_rup3`, read instruction by
## instruction: it is set after `create_fx` and nothing writes it again before
## `t_flight_call` picks it up. **2.0 against a vy of 12.0 is an initial angle
## of nine and a half degrees off vertical** -- so the victim does go up in a
## slight diagonal, and that is the data rather than a bug. Over the
## sixty-four frames of the arc it carries him about 128 units sideways.
##
## ## And it does NOT go straight into the part
##
## `away_x_vel` (0x00055ab0) negates the value when the opponent is to the
## right and calls `set_x_vel_player` (0x00055a68), which writes it into
## **`G[0xb8]` or `G[0x210]`** -- the two walk-velocity words `repell_func`
## arbitrates -- not into the part's own 0x18. `repell_func` then copies them
## into the part every frame on its way out.
##
## So a launched victim's drift is subject to the leash and the push-apart like
## any other movement, and it persists until something else writes those words.
## **This port's `_repell` skips entirely while either fighter is airborne**,
## so a victim in the air is not arbitrated the way the engine's is -- the
## simplification is in `_repell`'s own note and this is the other end of it.
##
## Every one of these leaves also takes rate 5 and animation 30, which is why
## RATE_FALL and SCKNOCKDOWN are shared:
##
##     t_fall_on_my_back      0.0     the plain backward fall
##     t_r_airpunch           3.0
##     t_airborn_hit_no_sound 3.5
##     t_r_post_shake         4.0     t_r_kano_roll, t_r_ind_charge the same
##     t_combo_airborn_hit    5.0     t_r_square the same
##     t_r_jade_prop          6.0
##
## Only the ones a Scorpion fight can reach are listed below; the rest are
## recorded here so the next character does not have to find them again.
const FALL_VX := {
	8: UPCUT_VX,     # t_r_uppercut -> t_rup3
	11: int(3.0 * ONE),                  # t_r_flip_punch, the airpunch family
}

## **Where the body comes to rest, and the one place this leaves the streams.**
##
## The stream for animation 30 is six frames and ends at SCKNOCKDOWN6;
## `find_last_frame` (0x00055428) walks to the word before the END and so
## returns that same frame. But `SCORPIONFRAMES` names **eight**, and skinning
## all eight says what the missing two are for -- lowest vertex against the
## stance's, and the body's own height:
##
##     124  SCKNOCKDOWN6   +0.18 h off the floor   0.40 h tall
##     125  SCKNOCKDOWN7   +0.02 h                 0.41 h
##     126  SCKNOCKDOWN8   -0.06 h                 **0.21 h**
##
##     249  SCSWEEPFALL4   +0.24 h                 0.44 h
##     250  SCSWEEPFALL5   +0.08 h                 0.58 h
##     251  SCSWEEPFALL6   -0.02 h                 **0.20 h**
##
## A fifth of a body tall with its lowest point ON the floor is a man lying
## flat. Frame 124 is not: it is a third of a metre up and still half folded,
## which is the pose that was being held and the reason a downed fighter looked
## like he had stopped halfway.
##
## **Neither 126 nor 251 appears in any of the 92 streams** -- the pointer block
## in `_nj_ani_data` is 92 long and `_character_anitabs2` points INTO it at
## index 73, so there is no third table to look in. Something reaches them by a
## path not yet found. Until it is, the landing plays them off the frame list
## directly, and that is a deliberate departure from the stream rather than an
## accident: the measurement and the game both say the body ends up flat.
## **How much blood each reaction draws**, from the parameter every
## `create_blood_proc` call site passes -- it lands in `obj->0x1c` and
## `mk3_bloodevent` stores it per player, capped at twelve.
##
## **A reaction that is not here never calls it.** `t_r_lo_punch`,
## `t_r_lo_kick`, `t_r_sweep`, the three `t_r_duck_*`, `t_r_roundhouse`, both
## `t_r_flip_*`, `t_r_elbow_knee` and `t_r_tusk_elbow` draw no blood at all,
## and that is the finding rather than a gap: a punch to the face bleeds and a
## sweep to the legs does not.
const BLOOD := {
	0: 2,        # t_r_hi_kick
	2: 3,        # t_r_hi_punch
	8: 1,        # t_r_uppercut
}

## **The end of the fall, and it is PART TWO of the same stream.**
##
## `find_part2` (0x00055450) is four instructions: walk the animation stream
## forward until a word reads ZERO and leave the pointer just past it. So a
## stream is not one list -- it is parts separated by a 0, and the knockdown
## has two of them. Raw, out of `_nj_ani_data` entry 30:
##
##     253 255 257 258 259 261   0   263 265   0
##     \_________ the tumble ________/    \_ flat _/
##
## which through `SCORPIONFRAMES.bin` is 119..124, then 125 and 126. The sweep
## fall (31) is the same shape: 246..249, then 250 and 251. The getup (33)
## even carries the sweep's frames as ITS part two.
##
## This is why the fall looked unfinished. The generator that built the table
## stopped at the first 0 -- the very marker `find_part2` looks for -- so the
## two frames that put him on the ground were never in it, and the earlier
## note in this file that "neither 126 nor 251 appears in any of the 92
## streams" was an artefact of that and is wrong.
##
## `t_reaction_land` (0x000425b8) is what plays them: `pl->0x40 = 30`,
## `find_ani_part2`, `pl->0x1c = 4`, `t_mframew`, then a three-frame wait and
## the getup. Rate 4, forward, and it holds the last one.
const FALL_TAIL := {
	30: [125, 126],                      # SCKNOCKDOWN7, SCKNOCKDOWN8
	31: [250, 251],                      # SCSWEEPFALL5, SCSWEEPFALL6
}
## `t_reaction_land`: `pl->0x1c = 4`, then `task->0xfc = 3`.
const RATE_LAND := 4
const LAND_WAIT := 3

## **Every attack has a RETRACTION, and this port was cutting it off.**
##
## The same 0 that splits the knockdown splits the attacks, and part two is the
## arm or the leg coming back. `t_retract_strike` (0x0004cb48) is what plays
## it: it clears the tag with `pl->0x20 = 0` and hands to
## `t_retract_strike_act`, which pushes `t_act_mframew` -- and neither touches
## `pl->0x40` or the rate. So the stream simply carries on from where the swing
## left it, at the same speed.
##
## Straight out of `_nj_ani_data` through SCORPIONFRAMES.bin:
##
##     SCHIPUNCH     80  81  82  |  83  84  85     a separate return
##     SCLOPUNCH    136 137 138  | 139 140 141     "
##     SCHIKICK      74 .. 79    |  78 77 76 75 74 the same frames, backwards
##     SCLOKICK     130 ..135    | 134 133 ..130   "
##     SCSPINHOOK   208 ..212    | 213 214 215
##     SCSWEEPKICK  252 ..256    | 257 258 259
##     SCUPPERCUT   271 ..275    | 274             one frame, a settle
##     SCCOMBO        8 ..11     |   9   8
##     SCKNEECOMBO  108 109 110  | 109 108
##     SCDUCKPUNCH   36  37  38  |  37  36  22
##     SCDUCKHIKICK  26 .. 29    |  28  27  26 22
##     SCDUCKLOKICK  33  34  35  |  34  34  22
##     SCJUMPKICK   105 106 107  | 106 105
##     SCFLIPUNCH    62  63  64  |  63  62
##     SCFLIPKICK    54  55  56  |  55  54
##
## The low punch is the one that looked broken: it stopped on 138, arm fully
## out, and snapped to the stance. The three ducking ones end on 22, which is
## the ducking pose -- they return to a crouch rather than to standing, which
## is exactly right and is not something anybody would have guessed.
## **Verified part by part against the streams, and the punches are NOT here.**
##
## The tails below are each animation's PART 2, which the cursor reaches by
## simply carrying on: `t_retract_strike` (0x0004cb48) clears the tag and hands
## to `t_retract_strike_act`, and neither touches `pl->0x40` or the rate, so the
## stream runs on from wherever the swing left it.
##
## **The two punches do not work that way and the old table here was wrong.**
## It listed SCHIPUNCH's tail as 83 84 85 -- but that is part 2, which is what
## `t_jhp5` plays as the SECOND JAB of the chain, not a retraction. The punches
## re-seat the cursor explicitly instead: `t_joy_un_hi_punch1` sets 0x40 = 14
## and walks one zero, `t_joy_un_hi_punch2` walks two, and `t_unhip1`
## (0x0002f704) then walks TWO MORE before playing. Three zeros and four zeros,
## so part 4 and part 5 -- which are [81, 80] and [86], the arm coming back and
## a settle. Those live in PUNCH_PART below, picked by which swing you were in.
##
## That mismatch is why this dict was emptied by hand: the retraction was
## playing a second jab and looked broken. It was.
## `_AnimSmoothWindowSize`, the word at 0x00171368. The front end borrows it
## at 0x28 and one other path at 0x14, but the value a fight runs with is 2.
const ANIM_SMOOTH_WINDOW := 2
## The ring is 64 entries: every index in the function is masked with 0x3f.
const ANIMHIST := 64


const ANI_TAIL := {
	8: [37, 36, 22],                     # SCDUCKPUNCH   back to the crouch
	9: [28, 27, 26, 22],                 # SCDUCKHIKICK  "
	10: [34, 34, 22],                    # SCDUCKLOKICK  34 twice, as written
	11: [274],                           # SCUPPERCUT    one frame, a settle
	16: [9, 8],                          # SCCOMBO
	17: [78, 77, 76, 75, 74],            # SCHIKICK      the swing, backwards
	18: [134, 133, 132, 131, 130],       # SCLOKICK      "
	19: [109, 108],                      # SCKNEECOMBO
	20: [257, 258, 259],                 # SCSWEEPKICK   forward, not reversed
	21: [213, 214, 215],                 # SCSPINHOOK    "
	23: [106, 105],                      # SCJUMPKICK
	24: [63, 62],                        # SCFLIPUNCH
	25: [55, 54],                        # SCFLIPKICK
	# 6 SCDUCKBLOCK and 12 SCBLOCK have NO tail: their part 2 is the start of
	# the next animation in the shared stream (SCDUCKTURN and SCDUCK), not a
	# return. Absent on purpose.
}


## **The two punch streams, as their real PARTS.**
##
## ani 14 and ani 15 are one contiguous block -- ani 15's pointer lands on what
## is ani 14's part 8 -- and the punch procs walk it with a cursor. Each swing
## proc plays whatever part the cursor sits on and leaves it at the next one;
## the retraction and cross-over procs SEAT the cursor at a numbered part.
## `next` is where the cursor ends up, following the stream's own jumps.
##
##     H1  t_joy_hi_punch seats it here (get_char_ani)
##     H2  what t_jhp5 plays after H1
##     H3  what t_jhp4 plays after H2; its jump sends the cursor back to H2,
##         so a held-up jab string alternates H2, H3, H2, H3...
##     H4  t_joy_un_hi_punch1 + t_unhip1  -- retract out of an A swing
##     H5  t_joy_un_hi_punch2 + t_unhip1  -- retract out of a B swing
##     H6  t_joy_punch_htm1   -- cross to the low punch, out of an A swing
##     H7  t_joy_punch_htm2   -- cross to the low punch, out of a B swing
##
## and L1..L7 the same for SCLOPUNCH through mth1/mth2. Note the cross parts
## MIX frames from both punches -- 83 is SCHIPUNCH4 and 140 is SCLOPUNCH5 --
## which is what makes them transitions rather than ordinary swings, and is the
## check that these are the right parts.
## `own` is which punch the PROC belongs to while this part plays, and it is
## not always the stream the part lives in. The cross parts are the catch: H6
## is ani 14's part 6, but `t_joy_punch_htm1` seats it and then installs
## `t_jmp5` -- a LOW punch swing. So the frames come out of the high stream
## while the fighter is already throwing the low punch, which is exactly what
## a transition is, and it decides the strike, the tag and which retraction
## the swing falls out to.
const PUNCH_PART := {
	"H1": {"f": [80, 81, 82], "next": "H2", "own": "H"},
	"H2": {"f": [83, 84, 85], "next": "H3", "own": "H"},
	"H3": {"f": [84, 83, 82], "next": "H2", "own": "H"},
	"H4": {"f": [81, 80], "next": "", "own": "H"},
	"H5": {"f": [86], "next": "", "own": "H"},
	"H6": {"f": [83, 140, 141], "next": "L3", "own": "L"},   # htm1 -> t_jmp5
	"H7": {"f": [84, 137, 138], "next": "L2", "own": "L"},   # htm2 -> t_jmp4
	"L1": {"f": [136, 137, 138], "next": "L2", "own": "L"},
	"L2": {"f": [139, 140, 141], "next": "L3", "own": "L"},
	"L3": {"f": [140, 139, 138], "next": "L2", "own": "L"},
	"L4": {"f": [137, 136], "next": "", "own": "L"},
	"L5": {"f": [86], "next": "", "own": "L"},
	"L6": {"f": [139, 140, 85], "next": "H3", "own": "H"},   # mth1 -> t_jhp5
	"L7": {"f": [139, 84, 82], "next": "H2", "own": "H"},    # mth2 -> t_jhp4
}

## `t_unhip1` sets `pl->0x1c = 2` before it plays, so both punches retract at
## rate 2 whichever swing they came out of.
const PUNCH_RETRACT_RATE := 2


## How long a knocked-down fighter lies there before getting up. **Chosen** --
## the engine counts it in a state that is not decompiled.
const DOWN_HOLD := 24

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
## **The block, measured end to end.**
##
## `t_do_block_hi` (0x0004cea0) is four lines: `stop_me_player`, animation
## index 12 into `pl->0x40`, `get_char_ani`, and then the pair
## `pl->0x1c = 3` / `pl->0x20 = 0x700` before it hands off to `t_act_mframew`.
## The 3 is the anirate; the 0x700 is a TAG, and `is_he_blocking` (0x0005837c)
## is what reads it back. `t_do_duck_block` (0x00030550) is the same function
## with animation 6 and the tag 0x701.
const RATE_BLOCK := 3

## `t_do_unblock_hi` (0x0004d7a0) does not play a release clip -- there is no
## such animation. It takes the block clip's LAST frame, steps back one
## (`0x40 -= 4`), waits four, steps back one more (`0x44`), waits four, and
## leaves. Two frames, backwards, four game frames each.
const UNBLOCK_RATE := 4
const UNBLOCK_FRAMES := 8

## `t_block_shake` (0x00044750) loops `pl->0x44` times -- and `t_weak3` sets
## that to 3, with `pl->0x48 = 2` frames a step. So a blocked hit is a
## twelve-frame judder and the blocker does not move: the loop ends on
## `stop_me_player`. **WHICH frames it jitters between is a reading**; the
## count and the timing are not.
const BLK_SHAKE_HOLD := 2
const BLK_SHAKE := 12

## **The run, measured end to end.**
##
## `run_setup` (0x00030fbc) is four calls: animation 0x46 into `pl->0x40` and
## `get_char_ani`, `init_anirate` with 3, `towards_x_vel` with 0x80000, and
## `group_sound` with 7. So: SCRUN at rate 3, eight units a frame TOWARD the
## opponent, and the run grunt.
const RUN_VX := int(8.0 * ONE)           ## measured, 0x80000 via towards_x_vel
const RUN_VOICE := 7                     ## measured, group_sound's index

## **The turbo bar is 48 and it drains one a frame.**
##
##     is_run_pressed    (0x0002f344)  joy & 0x40000; the bar must be non-zero,
##                                     and an empty one costs 40 frames
##     reduce_turbo_bar  (0x00030820)  one off the bar a frame, and the
##                                     penalty held AT 40 the whole time
##     RaiseTurboBars    (0x00057a90)  the penalty down one a frame, and only
##                                     when it is gone does the bar climb --
##                                     `cmp r2, #0x2f` so it stops at 48
##
## Which is why an emptied bar feels so much worse than a half-used one: the
## forty frames start counting from when you STOP, not from when you emptied
## it, and running keeps resetting them.
const RUN_MAX := 0x30                    ## measured, 48
const RUN_PENALTY := 0x28                ## measured, 40

## **Every attack carries its own animation AND its own rate, and this port
## had neither.** It played all of them off the move the button names, at the
## stance's inherited 6.
##
## Each `t_stat_do_*` / `t_do_*` proc is the same four lines -- the pattern
## `t_do_block_hi` and `run_setup` already showed -- an animation index into
## `pl->0x40`, a rate into `pl->0x1c`, a tag into `pl->0x20`:
##
##     t_stat_do_hi_kick    0x0004e660   ani 17  rate 1   tag 0x103
##     t_stat_do_lo_kick    0x0004e6cc   ani 18  rate 1   tag 0x104
##     t_stat_do_sweep_kick 0x0004e8c4   ani 20  rate 3   tag 0x10d
##     t_stat_do_roundhouse 0x0004eaa4   ani 21  rate from `_round_speeds`
##     t_stat_do_uppercut   0x0004fab4   ani 11  rate 2   tag 0x10e
##     t_stat_do_duck_punch 0x0004e814   ani  8  rate 3   tag 0x108
##     t_stat_do_duck_kickh 0x0004e7a4   ani  9  rate 3   tag 0x106
##     t_stat_do_duck_kickl 0x0004e734   ani 10  rate 2   tag 0x107
##     t_do_knee            0x00032a88   ani 19  rate 1   tag 0x109
##     t_do_elbow           0x00032b78   ani from `_ochar_elbow_animations`,
##                                       rate 1, tag 0x10a
##     t_do_jumpup_punch    0x0004d5c0   ani 24  rate 9
##     t_do_jumpup_kick     0x0004d54c   ani 23  rate 10
##     t_do_flip_punch      0x0004d3ec   ani 24  rate 12
##     t_do_flip_kick       0x0004d634   ani 25  rate 11
##
## Two of those are per-character byte tables rather than constants, and both
## agree with the rest for Scorpion (18): `_round_speeds` (0x001673b0) byte 18
## is 3, and `_ochar_elbow_animations` (0x001664bc) byte 18 is 16 -- SCCOMBO,
## which is what his elbow is the first frame of. The top bit of the elbow
## entry is a "this character has no elbow" flag and Scorpion does not carry
## it.
##
## The kicks at rate 1 are the visible half of this: a six-frame SCHIKICK at
## the inherited 6 took thirty-six game frames, and the engine gives it six.
##
## **The punches are the exception and it is a finding, not a gap.**
## `t_joy_un_hi_punch1` and `t_joy_un_lo_punch1` set the animation and go
## straight to `find_ani_part2` without touching the rate at all, so a jab runs
## at whatever the fighter was already carrying. -1 is that inheritance.
const STRIKE_ANI := {
	_Stk.HIKICK: 17, _Stk.LOKICK: 18, _Stk.HI_PUNCH: 14, _Stk.LO_PUNCH: 15,
	_Stk.SWEEP: 20, _Stk.DUCK_PUNCH: 8, _Stk.DUCK_KICKH: 9,
	_Stk.DUCK_KICKL: 10, _Stk.UPPERCUT: 11, _Stk.JUMP_PUNCH: 24,
	_Stk.JUMP_KICK: 23, _Stk.FLIP_KICK: 25, _Stk.FLIP_PUNCH: 24,
	_Stk.ROUNDH: 21, _Stk.KNEE: 19, _Stk.ELBOW: 16,
}
## **How long a strike is LIVE, and it is not a fraction of the clip.**
##
## `t_attk2` (0x000594d4) is the swing loop and it is four lines: set
## `pl->0x1c = pl->0x48`, call `strike_check_a0`, and if nothing was hit wait
## one frame and decrement `pl->0x44`. So the strike is checked once per game
## frame for exactly `pl->0x44` frames from the start of the move.
##
## `pl->0x48` in the same loop is the STRIKE ID, and reading it back out of
## every move proc confirms this port's numbering against the engine's: the
## roundhouse sets 13, the sweep 4, the knee 14, the elbow 15 -- which are the
## ids in umk3_strikes.gd, in order, with nothing assumed.
##
## The port used to make the strike live for the middle half of the clip, and
## said so. It does not have to guess any more.
const STRIKE_LIVE := {
	_Stk.HIKICK: 6, _Stk.LOKICK: 6,          # t_kick2       pl->0x44 = 6
	_Stk.HI_PUNCH: 5, _Stk.LO_PUNCH: 5,      # t_jhp4/t_jmp4            = 5
	_Stk.SWEEP: 1, _Stk.DUCK_PUNCH: 1,
	_Stk.DUCK_KICKH: 5, _Stk.DUCK_KICKL: 2,
	_Stk.UPPERCUT: 1, _Stk.ROUNDH: 3,
	_Stk.KNEE: 1, _Stk.ELBOW: 5,
	# The air attacks' own count has not been read; the whole swing stands in
	# while the fighter is off the ground. CHOSEN.
	_Stk.JUMP_PUNCH: 3, _Stk.JUMP_KICK: 3,
	_Stk.FLIP_PUNCH: 3, _Stk.FLIP_KICK: 3,
}

## **The retraction has its own rate, and it is not the swing's.**
##
## `t_kick2` (0x0004c9e4) sets `pl->0x1c = 3` immediately before handing to
## `t_retract_strike_act`, so a kick swings at 1 and comes back at 3 -- it
## snaps out and returns slowly, which is what a kick looks like.
## `t_stat_do_uppercut` sets 4 at the same moment. Everything else reaches the
## retraction through `t_retract_strike` (0x0004cb48), which sets the tag to
## zero and touches nothing else, so those come back at whatever they went out
## at.
const STRIKE_RETRACT := {
	_Stk.HIKICK: 3, _Stk.LOKICK: 3, _Stk.UPPERCUT: 4,
}

const STRIKE_RECOVERY := {
	_Stk.HI_PUNCH: 19,
}

## **A connected kick freezes.** `t_kick2` state 0x31a: if `pl->0x5c` came back
## non-zero -- the strike hit something -- it sets `task->0xfc = 0xc` and waits
## twelve frames before retracting. A kick that MISSES retracts at once. That
## pause is the weight of the hit, and this port did not have it.
const HIT_FREEZE := 12

const STRIKE_RATE := {
	_Stk.HIKICK: 1, _Stk.LOKICK: 1, _Stk.HI_PUNCH: -1, _Stk.LO_PUNCH: -1,
	_Stk.SWEEP: 3, _Stk.DUCK_PUNCH: 3, _Stk.DUCK_KICKH: 3,
	_Stk.DUCK_KICKL: 2, _Stk.UPPERCUT: 2, _Stk.JUMP_PUNCH: 9,
	_Stk.JUMP_KICK: 10, _Stk.FLIP_KICK: 11, _Stk.FLIP_PUNCH: 12,
	_Stk.ROUNDH: 3, _Stk.KNEE: 1, _Stk.ELBOW: 1,
}

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
	SPEARED, THROWN, FALLING, DOWN, GETUP, DEAD, VICTORY, STUNNED, UNBLOCK,
	RUN }

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
	## Which of those bits went down this frame -- `swscan`'s press set.
	var went := 0
	## Frames of hit-stop left: a connected kick holds its extended frame.
	var freeze := 0
	## **Which strike this attack resolved to, decided once.** The engine's
	## joy proc picks the knee, the elbow, the roundhouse or the sweep at the
	## moment the button goes down and jumps to THAT proc, which then sets the
	## animation and the rate. Recomputing it every frame -- which is what
	## this did -- let a fighter walk out of knee range mid-swing and change
	## which attack he was throwing.
	var strike := -1
	## **The punch chain window**, counting down exactly as `obj->a10` does
	## inside `t_punch_sleep` (0x00030eec). Five frames for either punch,
	## set from STRIKE_LIVE. Zero means the window is shut and the swing
	## retracts. Only the two punches ever open it -- see `_chain_punch`.
	var chain_left := 0
	## **Where the punch cursor sits**, as a PUNCH_PART key ("H1".."L7"), or
	## "" when this fighter is not in a punch. The swing procs read the part
	## here and leave the cursor at its `next`; the retraction and cross
	## procs seat it explicitly.
	var punch_part := ""
	## Which of the two swing procs is running: 0 is the A swing (t_jhp4 /
	## t_jmp4) and 1 is the B swing (t_jhp5 / t_jmp5). It decides which
	## retraction part a swing falls out to -- A takes part 4, B takes part 5
	## -- and which swing a cross-over hands to on the other side.
	var punch_swing := 0
	## **The engine renders the PAST.** `PlayerAutoSmoothAnims` (0x0005bb44)
	## keeps the last 64 frames a fighter displayed and draws the one sampled
	## `ANIM_SMOOTH_WINDOW` ticks ago, not the one the logic just chose. -1 is
	## an empty slot, and while any slot is empty the whole thing hard cuts.
	var hist := PackedInt32Array()
	var hist_cursor := 0
	## Where this fighter stood at the PREVIOUS tick. The simulation runs at a
	## fixed 60 Hz whatever the monitor does, so without these the same
	## position would be drawn two or three times running on a fast screen and
	## the extra frames would buy nothing.
	var prev_x := 0
	var prev_y := 0
	## Was this fighter off the ground on the previous pass? t_air_strike's
	## height test is a comparison against the floor every frame; this is how
	## the port notices the frame it stops being true on.
	var was_airborne := false
	## Was the stick held AWAY from the opponent when the button went down?
	## `is_stick_away` (0x00055df0) is what turns a high kick into a
	## roundhouse and a low kick into a sweep.
	var stick_away := false
	var table: Array = BT_STANCE
	## The engine's animation clock, from `init_anirate` and `next_anirate`:
	## `ani_rate` game frames per animation frame, counted down in `ani_count`.
	var ani := -1                ## which animation, by its engine id
	var ani_rate := 5
	var ani_count := 1
	var ani_index := 0
	## Which way the frame index walks. The unblock is the only thing in the
	## fight that plays a clip BACKWARDS, and it is what the engine does too.
	var ani_dir := 1
	var node = null

	## The word this fighter's own player produced this tick, kept because
	## `is_he_blocking` asks the JOYSTICK at the moment of the hit rather than
	## asking what state he is in.
	var raw := 0
	## Blocking low. `is_he_blocking` reads the stick's down bit, not a state.
	var blk_duck := false
	## Frames left of the judder a blocked hit causes.
	var blk_shake := 0
	## `set_no_block` (0x00054f20): `part->0x30 |= 4`, and a man carrying it
	## cannot guard however hard he holds the button. The spear's drag sets it.
	var no_block := false

	## The turbo bar, `G + 0x378 + player * 4`, and the lockout at `+ 0x388`.
	var turbo := RUN_MAX
	var turbo_pen := 0

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
	## **Stuck in the opponent.** The spear does not vanish when it connects:
	## `t_new_spear_proc`'s state 0x256 copies the OTHER object's x into the
	## projectile's x every frame, so the thing stays in him and the rope
	## stays drawn while `t_scorp_rope_pull` reels him in.
	var sp_stuck := false
	var sp_tex := 0              ## _SpearWhichTexture: the rope's frame
	var sp_node = null

	## `set_noedge`: the walls do not apply. The teleport sets it.
	var noedge := false
	## The teleport has left the ground, so landing ends it.
	var tele_air := false
	## And it keeps the landing frame, so the punch gets one.
	var tele_landed := false
	## Has he come back on the other side yet? The punch belongs after that.
	var tele_wrapped := false
	## Whoever's spear is dragging him, while St.SPEARED.
	var pulled_by = null
	## Which reaction is playing, so the knockdown knows what it came from.
	var react := -1
	## The x shift `t_collapse_on_ground` applies, held so it is undone on a
	## reset rather than accumulating.
	var collapsed := false
	## This fall ends the round: he does not get up again.
	var dying := false
	## This fall had a real launch, so LANDING is what ends it. A flat
	## knockdown never leaves the floor and cannot be timed that way -- which
	## is the bug that used to freeze a victim two ticks into his fall.
	var airborne_launch := false

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
		ani_dir = 1

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
		if ani_dir < 0:
			# The unblock walks down and stops at the first frame; the state's
			# own timer is what ends it.
			ani_index = maxi(0, ani_index - 1)
			return true
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

## Frames since somebody hit the floor.
var round_over := 0
## The screen shake, from `shake_a11`. Counted down in ticks.
var shake := 0
var shake_amp := 0.0
const SHAKE_FRAMES := 8
## The camera window, in engine units, so the teleport can wrap him across it.
var cam_mid := 0
var cam_span := float(CAM_WIDTH)
var hud = null
var blood = null
## The bindings. See umk3_input.gd -- set by umk3_main.gd, and the fight reads
## nothing at all without it, which is deliberate: there is no second place
## where a key becomes a bit.
var input = null

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
		# **Player two wears the second skin.** A mirror match is the normal
		# case here -- both fighters are Scorpion -- and the game ships a
		# `_DIFFUSE2` for every character for exactly this.
		n.set_palette(textures, i)
		f.node = n
		# One spear per fighter, because that is what `_DrawSpear[2]` and
		# `_SpearStartPos[2]` are.
		if blood == null:
			blood = _Blood.new()
			add_child(blood)
			blood.setup(textures)
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
		f.y = _ground_y() * ONE
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
		f.react = -1
		f.collapsed = false
		f.dying = false
		f.ani_dir = 1
		f.raw = 0
		f.blk_duck = false
		f.blk_shake = 0
		f.no_block = false
		f.went = 0
		f.strike = -1
		f.freeze = 0
		f.airborne_launch = false
		f.turbo = RUN_MAX
		f.turbo_pen = 0
		f.sp_live = false
		f.sp_stuck = false
		f.sp_thrown = false
		f.noedge = false
		f.tele_air = false
		f.pulled_by = null
		f.special = 0
		f.special_name = ""
		f.buf.clear()
		if f.sp_node:
			f.sp_node.clear()
	if blood:
		blood.clear()
	frame = 0
	round_over = 0
	if hud:
		hud.reset()


# --------------------------------------------------------------------- input
## One player's ten-bit word.
##
## **The bindings live in umk3_input.gd now**, one set per player for the
## keyboard and one for the pad, both live at once. What does not move is the
## word this returns: ten bits in the engine's order, which is the whole of
## what the fight downstream of here has ever received.
func _read_player(which: int) -> int:
	if which == 0 and not forced_seq.is_empty():
		var v: int = forced_seq[mini(_seq_at, forced_seq.size() - 1)]
		_seq_at += 1
		return v
	if forced[which] >= 0:
		return forced[which]
	if input == null:
		return 0
	return input.read(which)


## **`swscan` (0x00055e90), which runs once a frame for BOTH players at once.**
##
##     now = G->0x1c ; changed = G->0x20 ^ now ; G->0x20 = now
##     changed & now    the bits that just went DOWN -> the press events
##     changed & ~now   the bits that just came UP   -> the release events
##
## It matters that it runs for everyone every frame rather than inside the
## state that happens to be asking. This port only tracked the edge on the
## frames a fighter was standing free, so a button held through a block and
## then released and pressed again produced NO edge -- the remembered word
## still had it down from before.
func _swscan(f: Fight, raw: int) -> void:
	var now := raw & 0x3F0                      # the six button bits, 4..9
	f.went = now & ~f.prev_buttons
	f.prev_buttons = now


## Which of the six buttons went down this frame, or -1.
##
## **The index is the engine's own, and it is now verified end to end.**
## `swscan` hands a CHANGED BIT to `stack_switch_bits`, which turns the bit
## position into a row of `_swtab` (0x0016f10c), and each row carries the index
## `QueueAndJump` uses on the table at `pl->0x60`:
##
##     translated bit  4  ->  index 0    raw bit 4   HP
##     translated bit 16  ->  index 1    raw bit 5   LP
##     translated bit  5  ->  index 2    raw bit 6   BL
##     translated bit  6  ->  index 3    raw bit 7   HK
##     translated bit 17  ->  index 4    raw bit 8   LK
##     translated bit 18  ->  index 5    raw bit 9   RUN
##     translated bits 0..3 -> 6, 7, 8, 9            the four directions
##
## and `_bt_stance` (0x001655fc) reads, in those slots, `t_joy_hi_punch`,
## `t_joy_lo_punch`, `t_joy_block`, `t_joy_hi_kick`, `t_joy_lo_kick`, then a
## zero for run. Which is exactly BT_STANCE. The whole ten-bit contract is a
## measurement now rather than a reading of joy.c.
func _pressed_button(f: Fight, _raw: int) -> int:
	for i in 6:
		if f.went & (1 << (4 + i)):
			return i
	return -1


# ----------------------------------------------------------- the state machine
## How long an attack lasts: its own clip at its own rate.
func _move_frames(sid: int) -> int:
	if sid < 0:
		return RATE_STANCE
	var ani: int = int(STRIKE_ANI.get(sid, 0))
	var st := _stream(ani)
	if st.is_empty():
		return RATE_STANCE
	# Out at its own rate, back at the retraction's.
	var p1: int = (st[2] as Array).size()
	var p2: int = (ANI_TAIL.get(ani, []) as Array).size()
	return p1 * _strike_rate(sid) + p2 * _retract_rate(sid)


## The rate an attack plays at. -1 in the table means the engine never set one
## and the fighter keeps what he had -- 6 standing, 5 walking, whatever
## `init_anirate` last left in `pl->0x1c` (see the block comment above
## STRIKE_RATE). `f`, when given, is that fighter: pass it so a jab thrown
## while walking plays at the walk's own rate instead of always falling back
## to the stance's. Callers with no fighter in scope (the old flattened-stream
## `_move_frames`, `_retract_rate`'s own fallback) keep the stance default,
## same as before this was wired up.
func _strike_rate(sid: int, f: Fight = null) -> int:
	var r: int = int(STRIKE_RATE.get(sid, -1))
	if r < 0:
		r = f.ani_rate if f != null else RATE_STANCE
	return maxi(1, r + rate_bias)


## The rate the retraction comes back at.
func _retract_rate(sid: int) -> int:
	# `t_unhip1` (0x0002f704) sets `pl->0x1c = 2` before playing, so both
	# punches come back at 2 whichever swing they fell out of.
	if sid == _Stk.HI_PUNCH or sid == _Stk.LO_PUNCH:
		return maxi(1, PUNCH_RETRACT_RATE + rate_bias)
	if STRIKE_RETRACT.has(sid):
		return maxi(1, int(STRIKE_RETRACT[sid]) + rate_bias)
	return _strike_rate(sid)

func _recovery_frames(sid: int) -> int:
	return maxi(0, int(STRIKE_RECOVERY.get(sid, 0)))
	
## Which strike id this fighter's current move actually produces.
##
## **A button is not a move.** `t_joy_hi_kick` asks `is_stick_away` first and
## goes to `t_joy_roundhouse` if the stick is back; otherwise it goes through
## `t_knee_check`, which asks `get_x_dist` and substitutes a KNEE inside 74
## units. `t_joy_lo_kick` does the same with the SWEEP, and every high punch
## runs through `t_elbow_check` with the same 74. So two buttons make six
## attacks, and the fight was only ever producing two of them.
##
## `dist` is centre to centre, which is exactly what `get_x_dist` (0x0002f3a0)
## returns: |other.x - my.x|, no boxes involved.
##
## **The two kicks ask their two questions in OPPOSITE orders, and that is not
## a detail.** This function used to ask `away` first for both, which is right
## for the high kick and wrong for the low one.
##
##     t_joy_hi_kick (0x0002f2c8)   is_stick_away FIRST, then t_knee_check
##     t_joy_lo_kick (0x0002f4d4)   t_knee_check FIRST, then is_stick_away
##
## `t_joy_lo_kick` state 0 pushes `t_knee_check` and nothing else; only when
## the knee declines does state 0x236 read the stick. The decompilation's own
## comment on that state is "The knee check declined. Only now does the stick
## matter."
##
## So back+LK at close range is a KNEE, not a sweep. Back+HK at close range IS
## a roundhouse, because that one really does check the stick first.
func _resolve_strike(f: Fight, mv: int, dist: int, away: bool) -> int:
	if not MOVE_STRIKE.has(mv):
		return -1
	var id: int = MOVE_STRIKE[mv]
	match mv:
		MV_HI_KICK:
			# stick first -- t_joy_hi_kick state 0
			if away:
				return _Stk.ROUNDH
			if dist <= _Stk.CLOSE:
				return _Stk.KNEE
		MV_LO_KICK:
			# knee first -- t_joy_lo_kick state 0, stick only at 0x236
			if dist <= _Stk.CLOSE:
				return _Stk.KNEE
			if away:
				return _Stk.SWEEP
		MV_HI_PUNCH:
			if dist <= _Stk.CLOSE:
				return _Stk.ELBOW
	return id


## The strike record for whatever this fighter is doing, or an empty array.
func _strike_of(f: Fight, other: Fight = null) -> Array:
	var id := _strike_now(f, other)
	return [] if id < 0 else _Stk.STK[id]


## The same question, answered as the strike ID. The block half of a record --
## the chip damage and which of the 24 `_block_xfers` procs the victim goes
## into -- is looked up by id, so the id has to survive the lookup.
func _strike_now(f: Fight, _other: Fight = null) -> int:
	if f.st == St.SPECIAL:
		# **The spear is not here.** `_stk_scorp_spear` belongs to the
		# projectile, which is its own object with its own box -- see
		# `_spear_box`.
		if f.special == _Moves.SP_TELEPUNCH:
			return _Stk.SCORP_TELE
		return -1
	if f.st != St.ATTACK:
		return -1
	# Decided at the press, in `_start_attack`, and not touched since.
	return f.strike


## Where a strike's box sits in the world, as [x0, y0, x1, y1] in engine units
## with y growing DOWNWARD, which is the engine's own sense.
##
## **This is `strike_check_regs` (0x00059280), line for line.** x is the
## distance to the FAR edge and w is the width measured BACK toward the
## fighter, which is the opposite of what this function used to assume.
func _strike_box(f: Fight, stk: Array) -> Array:
	var x0: int
	if f.facing > 0:
		x0 = f.xi() + int(stk[STK_X]) - int(stk[STK_W])
	else:
		x0 = f.xi() - int(stk[STK_X])
	var y0: int = f.yi() + int(stk[STK_Y])
	return [x0, y0, x0 + int(stk[STK_W]), y0 + int(stk[STK_H])]


## A fighter's own body box, from `_FrameInfo2`. See BOX_W.
func _body_box(f: Fight) -> Array:
	var x0: int = f.xi() + BOX_LEFT
	var y0: int = f.yi() + BOX_TOP
	return [x0, y0, x0 + BOX_W, y0 + BOX_H]


static func _overlap(a: Array, b: Array) -> bool:
	return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


func _start_attack(f: Fight, mv: int, dist: int) -> void:
	f.st = St.ATTACK
	f.move = mv
	# **Seeded fresh, not carried over.** `was_airborne` only ever changes
	# inside St.ATTACK's own think (see below), so a grounded attack thrown
	# any time after an earlier AERIAL one found it still `true` from that
	# last air strike -- and on this attack's very first tick, `true and not
	# airborne` was already satisfied, so `_ground_after_air_strike` fired
	# before a single frame of the new attack's animation ever showed. Hit
	# detection ran fine off `f.strike`/`f.timer`, which is why the strike
	# still connected while the pose never moved.
	f.was_airborne = f.yi() < _ground_y()
	f.strike = _resolve_strike(f, mv, dist, f.stick_away)
	f.timer = _move_frames(f.strike) + _recovery_frames(f.strike)
	f.timer_total = f.timer
	f.connected = false
	# `obj->a10 = 5` in t_jhp4/t_jhp5/t_jmp4/t_jmp5, counted down by
	# t_punch_sleep. Only the two punches push that loop -- the kicks push
	# t_striker, which has no chain -- so only they open a window here.
	f.chain_left = 0
	f.punch_part = ""
	f.punch_swing = 0
	if f.strike == _Stk.HI_PUNCH or f.strike == _Stk.LO_PUNCH:
		f.chain_left = int(STRIKE_LIVE.get(f.strike, 0))
		# `t_joy_hi_punch` / `t_joy_lo_punch` do `obj->field40 = 14 or 15`
		# then `get_char_ani`, which parks the cursor at the stream's head.
		f.punch_part = "H1" if f.strike == _Stk.HI_PUNCH else "L1"
		# The cursor decides the length now, not the flattened stream.
		f.timer = _punch_timer(f) + _recovery_frames(f.strike)
		f.timer_total = f.timer
	if audio:
		# `t_stat_do_hi_kick`, `t_stat_do_uppercut` and `_sweep_sounds` are the
		# three that take `big_whoosh`; the punches and the flips take
		# `whoosh`. The roundhouse and the low kick are not in either list, and
		# they are put with the heavy kicks here.
		# **Every move proc, read one by one.** `rsnd_func`'s index, and
		# whether a `group_sound` goes with it:
		#
		#     t_jhp4, t_jmp4                       14 whoosh   + voice
		#     t_stat_do_duck_punch/kickh/kickl     14 whoosh   + voice
		#     t_do_flip_punch, t_do_flip_kick      14 whoosh   + voice
		#     t_do_jumpup_punch, t_do_jumpup_kick  14 whoosh   + voice
		#     t_stat_do_hi_kick, t_stat_do_lo_kick 15 big      + voice
		#     _sweep_sounds                        15 big      + voice
		#     t_stat_do_uppercut                   15 big      NO VOICE
		#
		# The uppercut is the only one that swings without a grunt, and that
		# is worth keeping rather than tidying away.
		#
		# `t_do_knee`, `t_do_elbow`, `t_joy_roundhouse` and `t_joy_sweep_kick`
		# play NOTHING of their own -- they are reached from a move that has
		# already made its noise -- so those inherit here, which is a reading
		# of the call graph rather than a measurement of its own.
		var id := f.strike
		var heavy := id == _Stk.UPPERCUT or id == _Stk.HIKICK 			or id == _Stk.ROUNDH or id == _Stk.SWEEP or id == _Stk.LOKICK
		audio.swing(heavy, id != _Stk.UPPERCUT)


## **The jab chain.** `t_punch_sleep` (0x00030eec) and state B of the four
## punch swings, together.
##
## The two punches -- and only the two punches -- push `t_punch_sleep` after
## their strike check. The kicks do not: `t_kick2` pushes `t_striker`, whose
## answer is "did it connect" and nothing else, so a kick has no chain and
## never had one. Same for the knee and the elbow, which share t_kick2's shape.
##
## What the loop actually compares is two BUTTON-QUEUE ENTRIES, not two
## buttons. `get_last_button` resets the ring cursor to the head and steps back
## one, so it answers "the entry before the head":
##
##   * holding queues nothing, the head does not move, the two readings are the
##     same word -- burn one of the five frames in `obj->a10` and sleep;
##   * pressing anything, INCLUDING the same button again, queues a fresh entry
##     with a fresh timestamp -- the readings differ and the chain is allowed.
##
## So it is tapped, not held, and re-tapping HP is the ordinary case.
##
## Then `am_i_facing_him` gates it: turn your back mid-string and it drops.
##
## Which continuation is the entry's HIGH halfword, which `stick_look_lr`
## (0x0005369c) establishes is the button code, and `four_button_switch`
## (0x00057274) fixes at HP 0, LP 1, BL 2, HK 3, LK 4, RUN 5 -- the same order
## as BT_STANCE here, and the same order `_pressed_button` returns.
##
## The four swings spell the branch out in opposite orders:
##
##     t_jhp4 (high)   sel 0 -> t_jhp5            sel 1 -> t_joy_punch_htm1
##     t_jhp5 (high)   sel 0 -> t_jhp4            sel 1 -> t_joy_punch_htm2
##     t_jmp4 (low)    sel 0 -> t_joy_punch_mth1  sel 1 -> t_jmp5
##     t_jmp5 (low)    sel 0 -> t_joy_punch_mth2  sel 1 -> t_jmp4
##
## **So the button you press is the punch you get**, whichever punch you are
## already in: HP lands in the high chain, LP in the low one, and BL, HK, LK
## or RUN all retract. "Continue" and "cross over" turned out to be one rule
## seen from two sides.
##
## **The cross-over lands on its real frames now.** `t_joy_punch_htm1/2` and
## `mth1/2` seat the animation cursor on a transition part and install the
## other punch's swing; those parts are H6, H7, L6 and L7 in PUNCH_PART, and
## each is three frames that MIX the two punches -- 83 is SCHIPUNCH4 and 140
## is SCLOPUNCH5 -- which is what makes them transitions. See `_continue_punch`.
func _chain_punch(f: Fight, other: Fight, raw: int) -> bool:
	if f.chain_left <= 0:
		return false
	if f.strike != _Stk.HI_PUNCH and f.strike != _Stk.LO_PUNCH:
		return false
	f.chain_left -= 1
	var b := _pressed_button(f, raw)
	if b < 0:
		# Nothing queued this frame. The window closes on its own.
		return false
	# `am_i_facing_him` -- the chain needs you still turned towards him.
	var toward := 1 if other.xi() >= f.xi() else -1
	if toward != f.facing:
		return false
	if b > 1:
		return false              # BL, HK, LK, RUN all retract
	var stream := String(PUNCH_PART[f.punch_part]["own"])
	var pressed := "H" if b == 0 else "L"
	if pressed == stream:
		# Same punch: the next swing proc plays the next part. H1->H2->H3,
		# and H3's own jump sends the cursor back to H2, so the string
		# alternates rather than running off the end.
		_continue_punch(f, String(PUNCH_PART[f.punch_part]["next"]),
			1 - f.punch_swing)
	else:
		# The other punch: seat the cursor on this stream's cross part --
		# 6 out of an A swing, 7 out of a B swing -- and hand to the other
		# stream's opposite swing, which is what htm1/htm2/mth1/mth2 do.
		var cross := stream + ("6" if f.punch_swing == 0 else "7")
		_continue_punch(f, cross, 1 - f.punch_swing)
	f.vx = 0
	return true


## Put the fighter into the next swing of a punch chain without going back
## through `_start_attack`, which would re-seat the cursor at the head.
func _continue_punch(f: Fight, part: String, swing: int) -> void:
	if part == "" or not PUNCH_PART.has(part):
		return
	# Which punch the PROC belongs to decides the strike and the tag -- which
	# for a cross part is the other stream from the one the frames live in.
	var stream := String(PUNCH_PART[part]["own"])
	var mv := MV_HI_PUNCH if stream == "H" else MV_LO_PUNCH
	f.st = St.ATTACK
	f.move = mv
	f.ani = MOVE_ANI[mv]
	# **No substitution on a chained swing.** The elbow lives in
	# `t_elbow_check`, which only `t_joy_hi_punch` pushes -- on the initial
	# press. The chain installs `t_jhp4`/`t_jhp5` directly, so a jab thrown
	# inside 74 units mid-string stays a jab and does not turn into an elbow.
	f.strike = _Stk.HI_PUNCH if stream == "H" else _Stk.LO_PUNCH
	f.punch_part = part
	f.punch_swing = swing
	f.ani_index = 0
	f.ani_count = 1
	f.ani_dir = 1
	f.connected = false
	f.chain_left = int(STRIKE_LIVE.get(f.strike, 0))
	f.timer = _punch_timer(f)
	f.timer_total = f.timer
	if audio:
		# Every swing makes its own noise: `rsnd_func(obj, 0xe)` and a
		# `group_sound` on the first frame of t_jhp4/t_jhp5/t_jmp4/t_jmp5.
		audio.swing(false, true)


## The end of an air attack, which is two calls and not a state change.
##
## `t_air_strike` (mkstat.c) is the loop every airborne attack runs, and this
## port did not have it. Its exit, once the fighter's y has reached the floor:
##
##     stop_me_player(obj)
##     ground_player(obj)
##
## `stop_me_player` (0x00055c04) clears 0x1c, clears the other object's 0x20
## and then applies a velocity -- which is zero, because 0x1c is where
## `set_x_vel_player` reads from. So it is a full stop, horizontal and
## vertical.
##
## `ground_player` (0x0005533c) is ten bytes: it copies the proc's 0x40 into
## the other object's 0x12, which is to say **it SNAPS him to the floor**
## rather than waiting for gravity to finish the job. This is the function
## `_tick`'s own comment calls "code that has not been read"; it has now been
## read, and this is it.
##
## The difference matters because the engine's height test is `>` against the
## floor, so the frame the move ends on is the frame he is AT or PAST it --
## and without the snap he ends the move a fraction below, or hangs a fraction
## above, depending on where gravity happened to put him.
func _ground_after_air_strike(f: Fight) -> void:
	# ground_player: he is on the floor, exactly, not approximately.
	f.y = _ground_y() * ONE
	# stop_me_player: both velocities, and the gravity that would restart one.
	f.vx = 0
	f.vy = 0
	f.g = 0
	f.st = St.STANCE
	f.table = BT_STANCE
	f.move = MV_NONE
	f.was_airborne = false


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
	var airborne := f.yi() < _ground_y()

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
		St.BLOCK:
			# **`t_joy_block_loop` (0x000301c4), state 0x283, every frame.**
			# It reads the stick, then the block bit, and NOTHING here is
			# edge triggered: the loop tail-calls itself for as long as
			# `check_block_bit` keeps coming back non-zero.
			#
			# That is the bug this fixes. The block was being started off
			# `_pressed_button`, which only fires on the frame a button goes
			# DOWN, so a held block lasted two frames and could never be
			# holding when a hit arrived.
			#
			# **Zeroed only once the shake's own loop ends, not every tick.**
			# `t_block_shake` calls `stop_me_player` -- which is what zeroes
			# the velocity -- exactly once, on the pass where its `a10` loop
			# runs out; every tick before that the pushback `t_block3` gave
			# him (`away_x_vel`, 2.0 in 16.16) is still live. Zeroing it every
			# tick regardless, which is what this did before, cancelled that
			# pushback the frame after it landed -- so a blocked hit never
			# actually slid the blocker back.
			if f.blk_shake > 0:
				f.blk_shake -= 1
				if f.blk_shake == 0:
					f.vx = 0
			if f.no_block:
				f.st = St.STANCE
				f.table = BT_STANCE
				return
			if raw & IN_BL:
				# Down while blocking is the duck block -- the loop hands off
				# to `t_joy_down`, which lands on `t_do_duck_block` and its
				# animation 6.
				f.blk_duck = (raw & IN_DOWN) != 0
				return
			# Let go: `t_do_unblock_hi`, two frames of the clip backwards.
			f.st = St.UNBLOCK
			f.timer = UNBLOCK_FRAMES
			f.timer_total = f.timer
			f.blk_shake = 0
			var clip := _stream(f.ani)
			if not clip.is_empty():
				f.ani_index = maxi(0, (clip[2] as Array).size() - 2)
			f.ani_rate = UNBLOCK_RATE
			f.ani_count = UNBLOCK_RATE
			f.ani_dir = -1
			return
		St.UNBLOCK:
			f.vx = 0
			# The release can be interrupted by grabbing block again, which is
			# what the loop's own state 0x28e path does.
			if raw & IN_BL:
				f.st = St.BLOCK
				f.ani_dir = 1
				f.ani_rate = RATE_BLOCK
				return
			if f.timer == 0:
				f.st = St.STANCE
				f.table = BT_STANCE
				f.ani_dir = 1
			return
		St.HIT:
			if f.timer == 0:
				f.st = St.STANCE
				f.table = BT_STANCE
			return
		St.FALLING:
			# **It ends when the CLIP does**, and that is the fix for a
			# fighter who froze mid-air.
			#
			# `t_fall_on_my_back` arms gravity with the velocity at zero, so
			# there is no arc to land from: he is on the floor the whole time
			# and the clip does the tumbling. The old test -- "not airborne
			# and vy past the apex" -- went true on the second tick, when
			# gravity had made vy positive but the half-unit of fall had not
			# yet been clamped away. Two ticks of a thirty-tick clip, and
			# whatever frame that left him on is where he stopped.
			# **`t_flight` ends when he lands.** A launched fighter is timed
			# by the floor, not by a counter; the counter is the backstop.
			var landed := false
			if f.airborne_launch and f.vy > 0 and f.yi() >= _ground_y():
				landed = true
			if f.timer == 0 or landed:
				f.airborne_launch = false
				f.vy = 0
				f.g = 0
				f.y = _ground_y() * ONE
				f.vx = 0
				if f.dying:
					_hit_the_floor(f)
					return
				f.st = St.DOWN
				# **Part two, at its own rate, and then the wait.** Long
				# enough for both frames to be seen: two at rate 4 plus the
				# three `t_reaction_land` sits on before the getup.
				var tail: Array = FALL_TAIL.get(f.ani, [])
				if tail.is_empty():
					f.timer = RATE_FALL + DOWN_HOLD
				else:
					f.timer = tail.size() * RATE_LAND + LAND_WAIT
				f.timer_total = f.timer
				# `shake_n_sound` (0x000424fc) is two lines and this had only
				# one of them: `pl->0x48 = 0x60006` into `shake_a11` -- the
				# same {6, 6} the uppercut itself shakes with -- and then
				# `rsnd_func(pl, 13)`, the ground thud, which was already
				# right.
				shake = SHAKE_FRAMES
				shake_amp = 6.0
				if audio:
					audio.fall()
			return
		St.DOWN:
			f.vx = 0
			if f.timer == 0:
				f.st = St.GETUP
				f.timer = _ani_length(
					ANI_SWEEPUP if f.react == 4 else ANI_GETUP, RATE_GETUP)
				f.timer_total = f.timer
			return
		St.GETUP:
			f.vx = 0
			if f.timer == 0:
				f.st = St.STANCE
				f.table = BT_STANCE
				f.react = -1
			return
		St.DEAD, St.VICTORY:
			# The round is over. Neither of them does anything else.
			f.vx = 0
			return
		St.ATTACK:
			# `t_kick2` state 0x31a: a connected kick waits twelve frames on
			# its extended frame before it starts coming back.
			if f.freeze > 0:
				f.freeze -= 1
				f.timer += 1
				return
			# **The height test runs every frame, not only at the end.**
			# t_air_strike checks `proc->field40 > MK3_FIELD12(part)` on
			# every pass of its loop -- the floor against where he is -- and
			# grounds him the moment it stops being true. So an air attack
			# that reaches the floor with clip left over ends THERE, rather
			# than carrying on into a move being played by a man standing up.
			if f.was_airborne and not airborne:
				_ground_after_air_strike(f)
				return
			f.was_airborne = airborne
			# The punch chain, before the timer is allowed to run out.
			if _chain_punch(f, other, raw):
				return
			if f.timer == 0:
				# **An air attack ends when he LANDS, not when the clip runs
				# out.** `t_wait_for_landing` (0x000574a4) sleeps one frame at
				# a time, asks `is_he_airborn` every pass and only unwinds
				# when the answer is no:
				#
				#     token 0       task->0xfc = 1 ; return 1
				#     token 0x15c3  get_his_action -> 0x610 ? unwind
				#                   is_he_airborn  -> no    ? unwind
				#                   otherwise sleep again
				#
				# This port ended the attack on its timer instead, so a kick
				# whose animation finished in the air left the fighter holding
				# its last pose, hanging there until he happened to touch the
				# floor. That is the floating, and it is not a missing
				# function -- the whole landing chain is decompiled and the
				# port simply did not use it.
				#
				# The clip is over either way, so the pose holds on its
				# last frame while the wait runs, which is what the engine
				# does too: nothing advances the animation during the wait.
				if airborne:
					# **Still in flight.** t_air_strike hands to
					# `t_flight_loop` once its counter runs out, and a flight
					# is one velocity against one gravity. Make sure there IS
					# a gravity: a fighter who reached this state with `g`
					# zeroed -- the way a landing zeroes it -- would hang
					# here for ever now that the move no longer ends on its
					# timer. That was the floating.
					if f.g == 0:
						f.g = GRAVITY
					return
				_ground_after_air_strike(f)
			return
		St.SPECIAL:
			if f.special == _Moves.SP_SPEAR:
				# The animation lets go of it; from there the projectile is
				# its own object with its own velocity, which is exactly the
				# shape `t_new_spear_proc` has.
				if not f.sp_thrown and f.ani_index >= SPEAR_THROW_FRAME:
					_throw_spear(f)
			elif f.special == _Moves.SP_TELEPUNCH:
				# `t_sctele_calla_1`: off one edge, on at the other.
				_tele_wrap(f)
				# It ends when he lands, not when the animation runs out: the
				# arc is nineteen frames and the clip is three.
				if airborne:
					f.tele_air = true
				elif f.tele_air:
					# **One more tick on the ground before the state ends.**
					# `_resolve_hits` runs after `_think`, so ending the move
					# on the landing frame threw away the frame the punch
					# actually arrives on.
					f.vx = 0
					if f.tele_landed:
						f.noedge = false
						f.st = St.STANCE
						f.table = BT_STANCE
						f.special = 0
						f.special_name = ""
					else:
						f.tele_landed = true
						if audio:
							audio.land()
				return
			if f.timer == 0:
				# **The rope outlives the throw.** Four frames of animation
				# against a flight of twenty and a drag after it: letting the
				# clip end the state put Scorpion back in his stance with his
				# spear still in the air.
				if f.special == _Moves.SP_SPEAR 						and (f.sp_live or other.pulled_by == f):
					f.st = St.THROWN
					f.vx = 0
					return
				f.st = St.STANCE
				f.table = BT_STANCE
				f.special = 0
				f.special_name = ""
			return
		St.THROWN:
			f.vx = 0
			if not f.sp_live and other.pulled_by != f:
				f.st = St.STANCE
				f.table = BT_STANCE
				f.special = 0
				f.special_name = ""
			return
		St.SPEARED:
			# `t_tugged_in_by_spear` state 0x44f: dragged at 8.0 toward
			# whoever threw it until `get_x_dist` comes inside 0x40, then
			# stopped and STUNNED.
			var puller = f.pulled_by
			if puller == null or absi(puller.xi() - f.xi()) <= PULL_STOP:
				f.pulled_by = null
				f.vx = 0
				f.st = St.STUNNED
				f.timer = STUN_FRAMES
				f.timer_total = f.timer
				f.table = BT_NULL
			else:
				f.vx = PULL_VX * (1 if puller.xi() > f.xi() else -1)
			return
		St.STUNNED:
			# State 0x45f: sixty-four frames of SCSTUNNED at rate 8, and any
			# strike ends it early -- `obj->0x5c` is the flag a hit sets, and
			# this state watches it. So the stun is a free hit, which is what
			# the move is for.
			f.vx = 0
			if f.timer == 0:
				f.st = St.STANCE
				f.table = BT_STANCE
				f.no_block = false
			return
		St.RUN:
			# `reduce_turbo_bar` runs every frame of it and the state ends
			# when the bar is gone -- plyrthread's 0x0003131e reads its
			# result and stops the player when it comes back zero.
			if f.turbo <= 0 or not (raw & IN_RUN) or not (raw & dir_f):
				f.st = St.STANCE
				f.table = BT_STANCE
				f.vx = 0
				return
			f.turbo -= 1
			f.turbo_pen = RUN_PENALTY
			f.vx = RUN_VX * f.facing
			# **The buttons still work.** Nothing in the run states calls
			# `stuff_buttons`, so `_bt_stance` is still installed at
			# `pl->0x60` and a punch out of a run is one press away.
			var rb := _pressed_button(f, raw)
			if rb >= 0 and f.table[rb]:
				var rmv: int = f.table[rb]
				f.stick_away = false
				if rmv == MV_BLOCK or rmv == MV_DUCK_BLOCK:
					f.st = St.BLOCK
					f.blk_duck = false
					f.table = BT_NULL
					f.ani_dir = 1
					f.vx = 0
				else:
					_start_attack(f, rmv, absi(other.xi() - f.xi()))
					f.vx = 0
			return
		St.JUMP:
			# A jump keeps whatever horizontal velocity it started with and
			# only gravity acts.
			if not airborne:
				f.vy = 0
				f.g = 0
				f.vx = 0
				f.y = _ground_y() * ONE
				f.st = St.STANCE
				f.table = BT_STANCE
				if audio:
					audio.land()
			else:
				var b := _pressed_button(f, raw)
				if b >= 0 and f.table[b]:
					f.stick_away = (raw & dir_b) != 0
					_start_attack(f, f.table[b], absi(other.xi() - f.xi()))
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
		f.tele_landed = false
		f.tele_wrapped = false
		f.noedge = false
		if audio:
			audio.special(f.special)
		if f.special == _Moves.SP_TELEPUNCH:
			# **It is a screen WRAP, and it goes backwards.** Three functions
			# had to be read to see it and every one of them says so:
			#
			#   tl_do_scorp_tele   face_opponent, then FLIP_MULTI -- so he
			#                      ends up facing away -- then set_noedge and
			#                      the three numbers, and hands off to the
			#                      proc at GOT 0x000f37f4
			#   that slot is       t_flight_call (0x00055aec), which copies
			#                      0x20 into the part's vy and 0x24 into its
			#                      gravity, and calls AWAY_X_VEL with 0x1c --
			#                      away, not towards
			#   t_sctele_calla_1   every frame: when his x passes the camera
			#                      edge he is travelling toward, it writes the
			#                      OPPOSITE edge into part->0x0e
			#
			# So he leaps AWAY from the opponent, flies off one side of the
			# screen and comes back on the other. That is why the move is
			# called a teleport, and it is why this port -- which sent him
			# forward at ten a frame and let him overshoot -- looked like it
			# was throwing him across the stage.
			f.facing = 1 if other.xi() >= f.xi() else -1
			f.vx = -TELE_VX * f.facing        # away_x_vel
			f.facing = -f.facing              # flip_multi
			f.vy = TELE_VY
			f.g = TELE_G
			f.noedge = true
			f.ani_rate = TELE_RATE
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
		if audio:
			audio.jump()                 # t_do_jump_up's group_sound 1
		# Straight up and angled are DIFFERENT TABLES -- which is why the
		# engine ships both bt_jump and bt_angle_jump.
		f.table = BT_ANGLE_JUMP if (raw & (dir_f | dir_b)) else BT_JUMP
		return
	elif raw & dir_f:
		f.st = St.WALK_F
		f.table = BT_STANCE
		vx = WALK_FORWARD[CHARACTER][WALK_SPEED] * f.facing
		# **Only a forward walk can become a run.** plyrthread asks
		# `is_run_pressed` on the branch that took `get_walk_info_f`, and the
		# backward branch at 0x00031352 compares against that same pointer
		# before it will fall through to the check -- so running backwards is
		# not a thing the state machine can express.
		if (raw & IN_RUN) and _run_pressed(f):
			f.st = St.RUN
			f.turbo_pen = RUN_PENALTY
			vx = RUN_VX * f.facing
			if audio:
				audio.group_voice(RUN_VOICE)
	elif raw & dir_b:
		f.st = St.WALK_B
		f.table = BT_STANCE
		vx = -WALK_BACKWARD[CHARACTER][WALK_SPEED] * f.facing
	else:
		f.st = St.STANCE
		f.table = BT_STANCE

	if btn >= 0 and f.table[btn]:
		var mv: int = f.table[btn]
		# `is_stick_away`, read once when the button goes down rather than
		# every frame: which move this is, is decided at that moment.
		f.stick_away = (raw & dir_b) != 0
		# **Getting INTO the block is a press; staying in it is a hold.**
		# `QueueAndJump` (0x000572b8) skips the table entirely for a release
		# event, so the table is dispatched on the press edge like every other
		# button -- and then `t_joy_block_loop` holds on the level. So a block
		# knocked out by an unguarded hit has to be pressed again, while one
		# that took a blocked hit comes back into the loop at state 0x28e and
		# keeps going on the bit alone.
		if mv == MV_BLOCK or mv == MV_DUCK_BLOCK:
			f.st = St.BLOCK
			f.blk_duck = (raw & IN_DOWN) != 0
			f.table = BT_NULL
			f.ani_dir = 1
			vx = 0
		else:
			_start_attack(f, mv, absi(other.xi() - f.xi()))
			vx = 0
	f.vx = vx


## `is_run_pressed` (0x0002f344), the half of it that is not the joy bit.
##
## An empty bar does not just refuse -- it writes 40 into the lockout on its
## way out, so hammering run on an empty bar keeps the bar empty.
func _run_pressed(f: Fight) -> bool:
	if f.turbo != 0:
		return true
	f.turbo_pen = RUN_PENALTY
	return false


## `RaiseTurboBars` (0x00057a90), once a frame for both of them.
func _raise_turbo() -> void:
	for f in fighters:
		if f.turbo_pen != 0:
			f.turbo_pen -= 1
		elif f.turbo <= RUN_MAX - 1:
			f.turbo += 1


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
	var stk := _strike_of(a, b)
	if stk.is_empty():
		return

	# **The teleport punch lands when HE does.** Its clip is three frames and
	# its flight is nineteen, so timing the strike off the animation made it
	# live only in the first third -- as he passed the opponent on the way up,
	# not when he arrived. `vy > 0` is the descent, which is the half of the
	# arc the punch belongs to.
	if a.st == St.SPECIAL and a.special == _Moves.SP_TELEPUNCH:
		# **`t_sctele_calla_2` (0x0003ee5c) is the only thing in the whole
		# teleport that calls `strike_check_a0`**, and `t_sctele_calla_1`
		# installs it at `obj->0x34` on the same frame it does the wrap. So the
		# punch exists only AFTER he has come back on the other side -- not on
		# the way out, which is where this port was checking it.
		if not a.tele_wrapped:
			return
	else:
		# **`t_attk2`'s own window**: live from the first frame of the move for
		# `pl->0x44` game frames, one check a frame. Not a fraction of the clip
		# any more -- see STRIKE_LIVE.
		var sid0 := _strike_now(a, b)
		var live: int = int(STRIKE_LIVE.get(sid0, 3)) * maxi(1, _strike_rate(sid0, a))
		var elapsed := a.timer_total - a.timer
		if elapsed > live:
			return
	if not _overlap(_strike_box(a, stk), _body_box(b)):
		return

	a.connected = true
	var sid := _strike_now(a, b)
	if HIT_FREEZE > 0 and (sid == _Stk.HIKICK or sid == _Stk.LOKICK):
		a.freeze = HIT_FREEZE
	var dmg: int = stk[STK_DMG]
	var away := 1 if b.xi() >= a.xi() else -1
	b.buf.clear()

	# **The block, out of `strike_check_regs` (0x00059280) at 0x593a4.**
	#
	# It calls `is_he_blocking`, and then, if he is:
	#
	#     r1 = word5 & 0xff                 the CHIP damage
	#     if (r1 < health[victim])  ->  blocked
	#     else                      ->  straight on into the damage path
	#
	# So a block that would take him to zero **does not hold**: the last hit
	# of a round always lands clean. That one `blt` is the whole rule, and it
	# is why nobody in Mortal Kombat dies guarding.
	if sid >= 0 and _is_he_blocking(b, stk):
		var chip: int = int(_Stk.CHIP[sid])
		if chip < b.health:
			b.health -= chip
			b.st = St.BLOCK
			b.table = BT_NULL
			b.connected = false
			# `t_blocked_start` -> `t_rst5`, and the judder of `t_block_shake`.
			b.blk_shake = BLK_SHAKE
			# **`t_block3`, the state the shake runs out of, is two more
			# reactions than "stand there and judder."** `field48 = 0x40004`
			# into `shake_a11` -- amplitude 4, the same {amp, amp} encoding as
			# the uppercut's {6, 6} above -- fires the screen shake on every
			# blocked hit, and `field1c = 0x20000` (2.0 in 16.16) into
			# `away_x_vel` pushes the blocker back. Both were dropped on the
			# floor entirely: this port zeroed the velocity instead of
			# applying it, and never shook the screen for a block at all.
			b.vx = int(2.0 * ONE) * away
			shake = SHAKE_FRAMES
			shake_amp = 4.0
			if audio:
				audio.block_hit(int(_Stk.BLOCK_IDX[sid]))
			return

	b.health -= dmg
	# `reaction_start_chores` (0x00044b0c) turns the victim to face whoever hit
	# him and stops him dead before the reaction's own velocity is applied.
	b.facing = 1 if a.xi() >= b.xi() else -1
	b.vx = 0
	_take_reaction(b, int(stk[_Stk.REACT]), away)
	b.table = BT_NULL                        # how the engine takes input away
	# **The reaction's own velocity, out of the reaction it names.** The strike
	# record's fifth word carries the index into `_reaction_table`, and the
	# `t_r_*` proc there either calls `away_x_vel` with a literal or does not
	# call it at all. See umk3_strikes.gd's REACT_VX: a jab pushes nobody, a
	# high kick pushes 4.5 a frame. What was here was one invented number
	# doubled above 24 damage.
	# **A knockdown's own leaf has already set the velocity** -- `t_rup3` gives
	# the uppercut 2.0 through `away_x_vel` -- and REACT_VX comes from the
	# `t_r_*` proc one level up, which for those reactions never calls it. The
	# more specific one wins; overwriting it here zeroed the uppercut's drift.
	if not KNOCKS_DOWN.has(int(stk[_Stk.REACT])):
		b.vx = int(_react_vx(stk) * ONE) * away
	if b.health <= 0:
		# **The round-ending hit always puts him on the floor.** Whatever the
		# reaction was, the loser collapses.
		_collapse(b)
	# **`t_r_uppercut` shakes the floor.** It calls `shake_a11` (0x000581e0)
	# with `obj->0x48 = 0x60006`, and `shake_a11` is one line:
	# `MKEvent_Add(1, 0, obj->0x48, 0)` -- event type 1, the screen shake, with
	# the two halves {6, 6} as its amplitude. It is the only reaction that does
	# it, and it is what makes an uppercut land like an uppercut.
	if int(stk[_Stk.REACT]) == _Stk.UPPERCUT:
		shake = SHAKE_FRAMES
		shake_amp = 6.0
	# `mk3_bloodevent`: at the victim's own position, away from the attacker.
	if blood and BLOOD.has(int(stk[_Stk.REACT])):
		@warning_ignore("integer_division")
		var up := BOX_H / 3
		blood.spawn(float(b.xi()), float(b.yi() + up),
			int(BLOOD[int(stk[_Stk.REACT])]), away)
	if audio:
		# **The reaction picks the sound.** `t_r_hi_punch` plays `smack`,
		# `t_r_lo_kick` plays `body_hit`, `t_r_uppercut` plays `big_smack`,
		# and the ninja elbow's reaction -- `t_r_tusk_elbow` -- plays `stab`.
		# Choosing Face2 or Body1 from whether the box sat above y = 40 got
		# several of them wrong.
		audio.hit_react(int(stk[_Stk.REACT]))
	if b.health <= 0:
		b.health = 0
		a.wins += 1
		a.st = St.VICTORY
		a.timer = _ani_length(ANI_VICTORY, RATE_STANCE)
		a.timer_total = a.timer
		a.table = BT_NULL
		a.vx = 0


## **`is_he_blocking` (0x0005837c), for a human player, line for line.**
##
## The order matters and so does what is NOT in it. There is no test that he is
## in a block state, no test of an animation, no window: the engine asks the
## joystick at the instant of the hit.
##
##     is_he_airborn(him)              -> airborne is never blocking
##     him.part->0x30 & 4              -> `set_no_block`, never blocking
##     check_block_bit(him)            -> the button must be DOWN right now
##     joy[him] & 2                    -> down too: duck block, stops anything
##     level & 2                       -> a LOW attack beats a standing block
##     otherwise                          blocked
##
## The fifth line is the seventh word of the strike record earning its keep.
## The sweep is the only one of the 27 with the bit set, which is exactly the
## rule a Mortal Kombat player knows: you cannot stand and block a sweep.
func _is_he_blocking(b: Fight, stk: Array) -> bool:
	if b.yi() < _ground_y():
		return false
	if b.no_block:
		return false
	if (b.raw & IN_BL) == 0:
		return false
	if b.raw & IN_DOWN:
		return true
	return (int(stk[STK_LEVEL]) & _Stk.LVL_LOW) == 0


## Put a fighter into the reaction this strike names.
##
## **Which animation** is REACT_ANI, and **whether it is a knockdown** is
## KNOCKS_DOWN -- both by the reaction id out of the strike record, the same
## number that already chooses the knockback and the sound.
func _take_reaction(f: Fight, react: int, away := 1) -> void:
	f.react = react
	var ani: int = int(REACT_ANI.get(react, ANI_HIT))
	if f.table == BT_DUCK and not KNOCKS_DOWN.has(react):
		ani = ANI_DUCK_HIT
	if KNOCKS_DOWN.has(react):
		_launch(f, away)
		return
	f.st = St.HIT
	f.timer = _ani_length(ani, maxi(1, RATE_STANCE + rate_bias))
	f.timer_total = f.timer


## Off the feet -- `t_fall_on_my_back`, transcribed. No launch: gravity armed,
## velocity zero, the clip at rate five doing the work.
func _launch(f: Fight, away: int) -> void:
	var clip: int = ANI_SWEEPFALL if f.react == 4 else ANI_KNOCKDOWN
	f.st = St.FALLING
	f.table = BT_NULL
	f.ani_rate = RATE_FALL
	f.vx = int(FALL_VX.get(f.react, 0)) * away
	if f.react == _Stk.UPPERCUT and not f.dying:
		# The one reaction with a launch of its own -- and not for the
		# round-ending collapse, which `t_collapse_on_ground` drives with no
		# velocity at all. See UPCUT_VY.
		f.vy = UPCUT_VY
		f.g = UPCUT_G
		# It stays up far longer than the clip runs, so the fall is timed by
		# the ARC -- `2 * vy / g` frames -- and the clip holds its end. The
		# state also ends the moment he touches the floor, which is the real
		# `t_flight` exit; the timer is only there so a fighter launched into
		# a ceiling cannot hang.
		f.timer = (2 * -UPCUT_VY) / maxi(UPCUT_G, 1) + 4
		f.airborne_launch = true
	else:
		f.vy = 0
		f.g = FALL_G
		f.timer = _ani_length(clip, RATE_FALL)
	f.timer_total = f.timer


## `t_collapse_on_ground`, transcribed.
##
## **It is two states, and running them as one was the bug.** State 0 does the
## chores -- `player_normpal`, `set_noedge`, `stop_me_player` -- and moves to
## 0x30c, which is where the knockdown PLAYS. Only the later state 0x30f calls
## `find_last_frame` and applies `_ochar_dead_adjusts`. Collapsing straight to
## the last frame skipped the fall entirely: he was on the floor before he had
## finished going there.
func _collapse(f: Fight) -> void:
	f.react = _Stk.UPPERCUT                  # SCKNOCKDOWN, what 0x1e resolves to
	f.dying = true
	f.noedge = true                          # set_noedge
	_launch(f, 0)


## State 0x30f: the body is on the LAST frame of the knockdown, shifted back by
## the character's own dead adjust so it lies where a body would, and the floor
## shakes.
func _hit_the_floor(f: Fight) -> void:
	f.st = St.DEAD
	f.vx = 0
	f.vy = 0
	f.g = 0
	f.y = _ground_y() * ONE
	f.timer = COLLAPSE_HOLD
	f.timer_total = f.timer
	if not f.collapsed:
		f.collapsed = true
		f.x += DEAD_ADJUST[CHARACTER] * f.facing * ONE
	if audio:
		audio.fall()                         # shake_n_sound


## How far back this strike's reaction throws the victim, in units a frame.
static func _react_vx(stk: Array) -> float:
	return float(_Stk.REACT_VX.get(int(stk[_Stk.REACT]), 0.0))


## `t_sctele_calla_1` (0x00040aa0), the half of it that matters here.
##
## It reads the camera window -- `G[0x468]` and that plus `0x18c + 3`, the same
## 399 the camera is built on -- and the fighter's own x velocity, and when he
## crosses the edge he is heading for it writes the opposite edge straight into
## `part->0x0e`. No interpolation, no fade: one assignment, which is what makes
## it read as a teleport rather than a very fast run.
##
## **The window is the engine's 399**, not the one this port happens to show.
## At the original 3:2 the two are the same and the wrap lands exactly on the
## screen edge, where it cannot be seen; on a wider window it happens a little
## way inside the frame. Using the visible span instead would put the edge
## beyond the arc's reach and the move would simply not teleport, which is what
## it did when this was tried the other way round.
## Is either fighter mid-teleport?
func _teleporting() -> bool:
	for f in fighters:
		if f.st == St.SPECIAL and f.special == _Moves.SP_TELEPUNCH:
			return true
	return false


func _tele_wrap(f: Fight) -> void:
	var half := CAM_WIDTH / 2
	var left := cam_mid - half
	var right := cam_mid + half
	if f.vx < 0 and f.xi() < left:
		f.x = right * ONE
		f.tele_wrapped = true
	elif f.vx > 0 and f.xi() > right:
		f.x = left * ONE
		f.tele_wrapped = true


## Let go of the spear. `t_new_spear_proc`, transcribed.
func _throw_spear(f: Fight) -> void:
	f.sp_thrown = true
	f.sp_live = true
	f.sp_stuck = false
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
	var s: Array = _Stk.STK[_Stk.SCORP_SPEAR]
	return [x0, y0, x0 + int(s[STK_W]), y0 + int(s[STK_H])]


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

	if f.sp_stuck:
		# State 0x256: the spear rides the man it is in, and lets go when the
		# pull is over.
		f.sp_x = other.x
		f.sp_y = other.y + SPEAR_DY * ONE
		if other.pulled_by != f:
			f.sp_live = false
			f.sp_stuck = false
		return

	f.sp_x += f.sp_vx
	var sx := f.sp_x >> FX
	if sx < WALL_L or sx > WALL_R:
		f.sp_live = false
		return
	if not _overlap(_spear_box(f), _body_box(other)):
		return

	# A standing block stops it: `_stk_scorp_spear`'s seventh word is 1, a high
	# attack, and that is what a standing block is for.
	if other.st == St.BLOCK:
		f.sp_live = false
		other.health -= 1
		if audio:
			audio.block()
		return

	# **It sticks. It does not disappear.** On the hit, `t_new_spear_proc`
	# hands the thread to `t_scorp_rope_pull`, zeroes the projectile's velocity
	# and goes to state 0x256 -- which does one thing per frame:
	#
	#     projectile->0x0e = otherguy->0x0e
	#
	# The spear follows the man it is in, so the rope is drawn from Scorpion's
	# hand to him the whole way back. Clearing `sp_live` here left the rope
	# gone and the victim sliding across the floor on his own.
	f.sp_stuck = true
	f.sp_vx = 0

	other.health -= int(_Stk.STK[_Stk.SCORP_SPEAR][STK_DMG])
	other.buf.clear()
	other.table = BT_NULL
	other.st = St.SPEARED
	other.pulled_by = f
	# `t_tugged_in_by_spear` (0x0007c504) calls `set_no_block` on the man it is
	# dragging, at offset +0x32 -- the second thing the state does. He cannot
	# guard while the rope has him, and he cannot guard through the stun that
	# follows either, because nothing clears the bit until he is free.
	other.no_block = true
	other.vy = 0
	other.g = 0
	other.y = _ground_y() * ONE             # ground_him
	if audio:
		# `t_stung_by_scorpion` (0x000a361c) calls `rsnd_func` with 3 -- the
		# STAB table -- and the victim's own hit voice. This was playing
		# Scorpion's line on the man who got hit.
		audio.speared()
	if other.health <= 0:
		other.health = 0
		f.wins += 1
		other.st = St.HIT
		other.pulled_by = null
		other.timer = _ani_length(ANI_HIT, maxi(1, RATE_STANCE + rate_bias))
		other.timer_total = other.timer


## `repell_func`, ported. `DisplayUpdate` calls it FIRST, before gravity and
## before the walls, so what it does to the two velocities is what everything
## after it then corrects.
##
## **It is two rules at opposite ends of the same measurement**, and neither
## build had either of them:
##
##     |dx| <= 0x3c   (60)    driven APART at 3.0 a frame
##     |dx| >  0x130  (304)   pulled together by half the excess, both moving
##
## The push is why two fighters cannot stand inside each other -- which they
## were doing here, walking through one another until an elbow had nothing in
## front of it to hit. The pull is why a two-player fight stays on one screen:
## past 304 units the excess is halved out of the gap every frame, so the pair
## converges rather than one being dragged.
##
## Between the two it only arbitrates the velocities: inside 0x3f, a fighter
## walking INTO the other has his speed halved, and if both are closing they
## both stop.
##
## **The vertical gate, now transcribed rather than skipped.** The original
## decides between the three behaviours with the fighters' own box edges --
## `part + 0x38` is the top and `part + 0x40` the bottom:
##
##     (pl0.bottom - 0x30) + y1  <  pl1.top + y2        p0 well ABOVE p1
##     y1 + pl0.top  <=  (pl1.bottom - 0x30) + y2       they OVERLAP
##     otherwise                                        p0 well BELOW p1
##
## With this port's box -- top 6, bottom 136 -- both of those collapse to the
## same number: the pair interact when their y's are within **82** units of
## each other, and only the leash applies when they are not. So a fighter
## launched by an uppercut stops being pushed once he is more than 82 units up,
## and is still reeled in by the leash the whole way, which is what the engine
## does and what "both on the ground" -- the gate this replaces -- did not.
##
## Still simplified: `Pp + 0x40` is a per-fighter height threshold with no
## writer anyone has found, and the countdown at `G + 0x456` likewise. Those
## choose between "setup" and "apart" in the two non-overlapping cases; here
## the non-overlapping cases always take the leash-only path.
const REPELL_OVERLAP := 82               ## (BOX_TOP + BOX_H - 0x30) - BOX_TOP
func _repell() -> void:
	var a := fighters[0]
	var b := fighters[1]
	var overlap := absi(a.yi() - b.yi()) <= REPELL_OVERLAP

	var x1 := a.xi()
	var x2 := b.xi()
	var adx := absi(x2 - x1)
	var vx1 := a.vx
	var vx2 := b.vx

	if overlap and adx <= NEAR_GAP:
		# apart:
		if x1 >= x2:
			vx1 = PUSH_VEL
			vx2 = -PUSH_VEL
		else:
			vx1 = -PUSH_VEL
			vx2 = PUSH_VEL
	elif overlap and adx <= 0x3f:
		# arbitrate_1 / arbitrate_2, in that order: whichever fighter is moving
		# toward the other drags both, and two closing fighters stop.
		if vx1 != 0 and ((vx1 < 0 and x1 > x2) or (vx1 > 0 and x1 < x2)):
			if (vx1 < 0 and vx2 > 0) or (vx1 > 0 and vx2 < 0):
				vx1 = 0
				vx2 = 0
			else:
				vx1 = vx1 >> 1
				vx2 = vx1
		elif vx2 != 0 and ((vx2 < 0 and x1 < x2) or (vx2 > 0 and x1 > x2)):
			if (vx2 < 0 and vx1 > 0) or (vx2 > 0 and vx1 < 0):
				vx1 = 0
				vx2 = 0
			else:
				vx2 = vx2 >> 1
				vx1 = vx2

	# check: the leash. `set_noedge` is the same opt-out the walls use, so a
	# teleport in flight is not reeled in either.
	if adx > FAR_GAP and not a.noedge and not b.noedge:
		var excess := adx - FAR_GAP
		# **The clamps happen whether or not the move does** -- they sit before
		# the branch that skips the rest in the original, and moving them after
		# it would be tidier and wrong.
		var shift := 0
		if x1 >= x2:
			vx2 = maxi(vx2, 0)
			vx1 = mini(vx1, 0)
			if excess > 3:
				shift = -(excess >> 1)
		else:
			vx2 = mini(vx2, 0)
			vx1 = maxi(vx1, 0)
			if excess > 3:
				shift = excess >> 1
		if shift != 0:
			a.x += shift * ONE
			b.x -= shift * ONE

	a.vx = vx1
	b.vx = vx2


## One 60 Hz frame.
func tick() -> void:
	for f in fighters:
		f.prev_x = f.x
		f.prev_y = f.y
	var raw := [_read_player(0), _read_player(1)]
	last_raw = raw[0]
	last_special = ""
	if fighters[0].st == St.SPECIAL and fighters[0].timer == fighters[0].timer_total:
		last_special = fighters[0].special_name

	for i in 2:
		# **Kept on the fighter.** `is_he_blocking` runs inside the ATTACKER's
		# hit check and asks the VICTIM's joystick, so the victim's word has
		# to still be around when the hit is resolved.
		fighters[i].raw = int(raw[i])
		_swscan(fighters[i], raw[i])
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
		var n: int = _frames_of(f).size()
		if f.st == St.ATTACK and f.freeze > 0:
			continue
		var anim_loop: bool = s[1]
		
		if f.st == St.ATTACK and f.strike == _Stk.HI_PUNCH:
			anim_loop = false
		if not f.tick_ani(n, anim_loop):
			continue
		# Crossing into part two is where the retraction's own rate starts.
		if f.st == St.ATTACK and f.strike >= 0:
			var p1: int = (s[2] as Array).size()
			if f.ani_index >= p1:
				f.ani_rate = _retract_rate(f.strike)
		if audio and (f.st == St.WALK_F or f.st == St.WALK_B):
			# Two footfalls in the cycle. WHICH frames they land on is a choice:
			# the clip names them SCWALK1..9 and nothing marks contact.
			@warning_ignore("integer_division")
			var half := n / 2
			if f.ani_index == 0 or f.ani_index == half:
				audio.step()
	_raise_turbo()
	if shake > 0:
		shake -= 1
	if blood:
		blood.tick()
	if hud:
		hud.health = [fighters[0].health, fighters[1].health]
		hud.wins = [fighters[0].wins, fighters[1].wins]
		hud.run = [fighters[0].turbo * 100 / RUN_MAX,
			fighters[1].turbo * 100 / RUN_MAX]
		hud.tick()
	_resolve_hits(fighters[0], fighters[1])
	_resolve_hits(fighters[1], fighters[0])
	_step_spear(fighters[0], fighters[1])
	_step_spear(fighters[1], fighters[0])

	# **First, before gravity and before the walls** -- which is where
	# `DisplayUpdate` calls it.
	_repell()

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
		if f.yi() > _ground_y():
			f.y = _ground_y() * ONE
			if f.vy > 0:
				f.vy = 0

	# The round is over once somebody is dead. Give the collapse and the
	# victory pose time to play before the next one starts.
	if fighters[0].st == St.DEAD or fighters[1].st == St.DEAD:
		round_over += 1
		if round_over > 180:
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
		St.THROWN:
			# `t_scorp_rope_pull` (0x0007c5fc) calls `get_char_ani2` with
			# index 9 -- and entry 9 of the ninjas' SECOND animation table
			# (0x001598b0) is SCSPEAR1..4, the same four frames as the throw.
			# So the thrower keeps playing the spear clip the whole time the
			# rope is out instead of snapping back to a stance, which is what
			# it was doing.
			return [ANI_SPEAR, RATE_PULL]
		St.ATTACK:
			if f.strike >= 0 and STRIKE_ANI.has(f.strike):
				return [int(STRIKE_ANI[f.strike]), _strike_rate(f.strike, f)]
			return [MOVE_ANI[f.move], -1]
		St.HIT:
			if f.react >= 0 and REACT_ANI.has(f.react) 					and f.table != BT_DUCK:
				return [int(REACT_ANI[f.react]), -1]
			return [ANI_DUCK_HIT if f.table == BT_DUCK else ANI_HIT, -1]
		St.FALLING:
			return [ANI_SWEEPFALL if f.react == 4 else ANI_KNOCKDOWN, -1]
		St.DOWN, St.DEAD:
			# The clip does not change -- the SETTLE is drawn straight from
			# FALL_TAIL in `_pose`, because those two frames are not in any
			# stream and so cannot be reached through one.
			return [ANI_SWEEPFALL if f.react == 4 else ANI_KNOCKDOWN, -1]
		St.GETUP:
			return [ANI_SWEEPUP if f.react == 4 else ANI_GETUP, RATE_GETUP]
		St.VICTORY:
			return [ANI_VICTORY, RATE_STANCE]
		St.STUNNED:
			return [ANI_STUNNED, RATE_TUGGED]
		St.SPEARED:
			# `t_tugged_in_by_spear` sets rate 8 -- slow, because he is being
			# dragged rather than reacting.
			return [ANI_HIT, RATE_TUGGED]
		St.RUN:
			return [ANI_RUN, RATE_RUN]
		St.BLOCK:
			# 12 standing, 6 ducking -- `t_do_block_hi` and `t_do_duck_block`
			# are the same four lines with a different index -- both at 3.
			return [ANI_DUCK_BLOCK if f.blk_duck else ANI_BLOCK, RATE_BLOCK]
		St.UNBLOCK:
			# The same clip. There is no release animation in the character at
			# all; the engine walks this one backwards.
			return [ANI_DUCK_BLOCK if f.blk_duck else ANI_BLOCK, -1]
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


## The frames a fighter is actually playing: the clip, plus its retraction
## when he is swinging. Only an ATTACK gets the tail -- the knockdown's part
## two is the landing and `t_reaction_land` places it itself, and the getup's
## is another clip's frames entirely.
func _frames_of(f: Fight) -> Array:
	# **A punch plays the part its cursor is on, not the stream's head.**
	# That is the whole difference between the punches and everything else:
	# a kick swings part 1 and returns through part 2 every single time,
	# while a jab walks H1, H2, H3, H2, H3... and falls out to a different
	# retraction depending on which swing it was in when the window shut.
	if f.st == St.ATTACK and f.punch_part != "" and PUNCH_PART.has(f.punch_part):
		var part: Dictionary = PUNCH_PART[f.punch_part]
		var out: Array = (part["f"] as Array).duplicate()
		return out + _punch_tail(f)
	var st := _stream(f.ani)
	if st.is_empty():
		return []
	var frames: Array = st[2]
	if f.st == St.ATTACK and ANI_TAIL.has(f.ani):
		return frames + (ANI_TAIL[f.ani] as Array)
	return frames


## How long the punch on the cursor lasts: its swing part at the swing's rate
## plus its retraction at rate 2. The same split `_move_frames` makes for
## everything else, except the parts come from the cursor instead of from the
## flattened stream -- which matters because H3 is not the same length as H1.
## `PlayerAutoSmoothAnims` (0x0005bb44), which is where the blend factor comes
## from and it is nothing like a clock.
##
## Every tick the frame just chosen goes into a 64-entry ring, and the frame
## RENDERED is the one sampled `ANIM_SMOOTH_WINDOW` ticks earlier. How long
## that sampled frame was held on either side decides whether it is drawn on
## its own or blended into its neighbour:
##
##     hardCut = (0x3f - window >= back) ? (fwd >= window) : 1
##
## with `back` counting matching entries before the sample (capped at 0x1f)
## and `fwd` after it (capped at 0x3f). A frame held two ticks or more after
## the sample is drawn alone. So at rate 3 -- the punches -- everything hard
## cuts, and at rate 1 -- the kicks swing at 1 -- it blends. That is the
## engine's own answer to why some moves look smooth and some look stepped,
## and this port had it as all-or-nothing in both directions: first always
## blended, which deformed the model, then never, which made everything step.
##
## **The factor degenerates.** `mid` is built from the two run lengths and
## compared against `sample`, which is `cursor - window` and grows without
## bound, so after the opening ticks of a round the first branch is
## unreachable and `t` settles at almost exactly 0.5. That is what the code
## does; whether the authors meant a ring-relative index there is not
## knowable from here and is not guessed at. The comparison is transcribed as
## written -- 0x0005bd12, `vcmpe.f32 s12, s14`, with s8 loaded from
## `cursor - AnimSmoothWindowSize` at 0x0005bb92.
##
## Returns [frameA, frameB, t] in the ENGINE's sense, where t = 0 yields
## frameB -- `LerpVector3` is `a*t + b*(1-t)`.
func _smooth(f: Fight, cur: int) -> Array:
	if f.hist.size() != ANIMHIST:
		f.hist.resize(ANIMHIST)
		f.hist.fill(-1)
		f.hist_cursor = 0
	f.hist[f.hist_cursor & 0x3f] = cur
	var window := ANIM_SMOOTH_WINDOW
	var sample := f.hist_cursor - window
	var any_empty := false
	for k in ANIMHIST:
		if f.hist[k] == -1:
			any_empty = true
			break
	var held: int = f.hist[sample & 0x3f]
	var back := 0
	var k := sample - 1
	while f.hist[k & 0x3f] == held and back < 0x1f:
		back += 1
		k -= 1
	var fwd := 0
	var j := sample + 1
	while f.hist[j & 0x3f] == held and fwd < 0x3f:
		fwd += 1
		j += 1
	var frame_after: int = f.hist[j & 0x3f]
	var frame_before: int = f.hist[k & 0x3f]
	var hard_cut := (fwd >= window) if (0x3f - window >= back) else true

	f.hist_cursor += 1

	if hard_cut or any_empty or held < 0:
		return [held if held >= 0 else cur, held if held >= 0 else cur, 0.0]

	var mid := float(back) + (float(back + 1 + fwd) + 1.0) * 0.5
	if mid > float(sample):
		var t := 0.5 + 0.5 * (float(sample) - float(back)) / (mid - float(back))
		return [frame_before, held, t]
	var t2 := 0.5 * (float(sample) - mid) / (float(j) - mid)
	return [held, frame_after, t2]


func _punch_timer(f: Fight) -> int:
	if f.punch_part == "" or not PUNCH_PART.has(f.punch_part):
		return 0
	var swing: int = (PUNCH_PART[f.punch_part]["f"] as Array).size()
	var tail: int = _punch_tail(f).size()
	return swing * maxi(1, _strike_rate(f.strike, f)) 		+ tail * _retract_rate(f.strike)


## The retraction a punch swing falls out to: part 4 out of an A swing and
## part 5 out of a B swing, in whichever of the two streams the cursor is in.
## `t_joy_un_hi_punch1` walks one zero and `t_unhip1` two more (part 4);
## `t_joy_un_hi_punch2` walks two and `t_unhip1` two more (part 5).
func _punch_tail(f: Fight) -> Array:
	if f.punch_part == "":
		return []
	var stream := String(PUNCH_PART[f.punch_part]["own"])
	var key := stream + ("4" if f.punch_swing == 0 else "5")
	if not PUNCH_PART.has(key):
		return []
	return (PUNCH_PART[key]["f"] as Array).duplicate()


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
	var frames: Array = _frames_of(f)
	var n := frames.size()
	var idx: int = clampi(f.ani_index, 0, n - 1)
	# **The teleport's clip is a leap and then a punch, and they are two
	# different halves of the move.** `tl_do_scorp_tele` flies him backwards
	# and `t_sctele_calla_2` -- installed at the wrap -- is what throws the
	# punch. Letting the three frames run on the flight's own clock left him
	# holding SCTELEPUNCH1, face down, for ten frames of travelling the other
	# way, which is the pose that looked wrong.
	#
	# So: the leap frames while he flies, the punch frame once he is back.
	# **Both ends of the settle, and they are different poses.**
	#
	# The clip stops at a frame that is still off the floor, and the frame list
	# carries two more. Their measurements say what each is for:
	#
	#     125 SCKNOCKDOWN7  +0.02 h, 0.41 h tall -- on the ground, propped up
	#     126 SCKNOCKDOWN8  -0.06 h, 0.21 h tall -- flat
	#
	# and SCGETUP1, the frame the getup starts from, is 0.40 h tall at -0.03 h
	# -- the same posture as 125. So a man who is going to stand up rests on
	# 125 and the getup carries on from exactly there, while a man who has lost
	# the round goes on to 126. `t_collapse_on_ground` is the only thing in the
	# fight that forces a held final frame, which is what makes the second one
	# the DEFEAT rather than every knockdown.
	if f.st == St.DOWN or f.st == St.DEAD:
		var tail: Array = FALL_TAIL.get(f.ani, [])
		if not tail.is_empty():
			# Part two plays FORWARD at rate 4 and holds its last frame --
			# and it is the same two frames whether the round is over or
			# not. The earlier version showed only the first of them unless
			# the fighter was dead, which is the missing end of the fall.
			var gone := f.timer_total - f.timer
			@warning_ignore("integer_division")
			var at: int = clampi(gone / RATE_LAND, 0, tail.size() - 1)
			f.node.set_pose(int(tail[at]), int(tail[at]), 0.0)
			return

	# `t_block_shake`: one frame forward, hold, one frame back, hold, three
	# times over. The blocker does not move -- the loop ends on
	# `stop_me_player` -- so this is the whole of what a blocked hit looks
	# like from his side.
	if f.blk_shake > 0 and n > 1:
		@warning_ignore("integer_division")
		var phase := (f.blk_shake / BLK_SHAKE_HOLD) % 2
		idx = clampi(idx - phase, 0, n - 1)
		f.node.set_pose(frames[idx], frames[idx], 0.0)
		return

	if f.st == St.SPECIAL and f.special == _Moves.SP_TELEPUNCH and n >= 3:
		idx = 2 if f.tele_wrapped else mini(f.ani_index, 1)
		f.node.set_pose(frames[idx], frames[idx], 0.0)
		return

	# **The engine does not blend on a clock, and mostly does not blend at
	# all.** What `umk3_fighter.gd` used to call "what the engine does" was a
	# fraction of the animation counter, and there is no such thing anywhere
	# in the binary. `next_anirate` (0x0005a680) counts down and, while the
	# counter is above zero, RETURNS -- the displayed frame does not move.
	# Steps, not a ramp.
	#
	# The real smoothing is `PlayerAutoSmoothAnims` (gamecode/Players.c): a
	# 64-entry ring of the frames this fighter has displayed, sampled
	# `AnimSmoothWindowSize` ticks IN THE PAST -- 2 by default, the word at
	# 0x00171368 -- with the blend chosen from how long the sampled frame was
	# held on either side:
	#
	#     hardCut = (0x3f - window >= back) ? (fwd >= window) : 1
	#
	# So a frame held for two ticks or more after the sample is a HARD CUT:
	# both frame slots get the same number and t goes to 0. At our rates that
	# is nearly always, which is why this now cuts.
	#
	# Blending two poses that are not adjacent in time is what deformed the
	# model -- and the cross-over parts made it obvious, because H6 runs
	# SCHIPUNCH4 straight into SCLOPUNCH5 and half-way between those two is
	# not a pose anybody drew.
	#
	# **Not yet 1:1:** the narrow case where the engine DOES blend, for a
	# frame held fewer than two ticks. Reproducing it needs
	# PlayerAutoSmoothAnims read against its own disassembly first -- its
	# `mid > sample` test compares a run length against an unbounded cursor,
	# which does not typecheck as transcribed, and guessing at it is how the
	# invented fraction got here in the first place. Hard-cutting everything
	# is the safe half of the truth, not the whole of it.
	# **Blend inside the clip, and never across its end.**
	#
	# The engine's own smoothing is `PlayerAutoSmoothAnims` and `_smooth`
	# below carries the reading of it -- a 64-entry ring, a sample two ticks
	# in the past, a hard cut whenever the sampled frame was held that long.
	# It is not used for the pose, and the reason is worth writing down
	# rather than quietly dropping:
	#
	#   * it renders two ticks LATE, and at this port's 60 Hz logic tick that
	#     is two of the three frames a punch has. Short clips disappeared
	#     into the delay. Whether the original's logic ran at 60 or at 30 is
	#     the one number `umk3_main.gd` still calls honestly open, and the
	#     delay only makes sense once that is settled.
	#   * its factor degenerates to ~0.5 (see `_smooth`), so what it buys on
	#     the frames it does blend is a permanent half-step rather than a
	#     ramp.
	#
	# **THE POSES DO NOT INTERPOLATE, and the reason is the data.**
	#
	# This has now been tried three ways and looked wrong three times: as a
	# clock fraction between consecutive frames, as a blend of everything
	# (F12), and as a blend inside one clip. Each deformed the fighter, and
	# the last one was the mildest but still visibly strange.
	#
	# The cause is not a bug in the blending. `SCHIPUNCH` is THREE FRAMES --
	# 80, 81, 82 -- for a whole punch. These are not keyframes of a smooth
	# curve sampled densely enough to interpolate; they are three drawings.
	# Half way between the first and the second is a posture nobody ever
	# made, and no amount of getting the maths right will invent one.
	#
	# The engine agrees. `PlayerAutoSmoothAnims` hard cuts whenever a frame
	# is held two ticks or more, which at these rates is nearly always, and
	# the little it does blend it blends between samples TWO TICKS APART in
	# its own history rather than between a clip's keyframes.
	#
	# So the pose steps, exactly as the original steps. What does interpolate
	# is POSITION, in `_place` -- that is real smoothness at a high frame
	# rate and it cannot deform anything, because a fighter's place in the
	# world is a number and not a drawing.
	f.node.set_pose(frames[idx], frames[idx], 0.0)


func _scene_x(f: Fight) -> float:
	return float(f.xi()) * scale_units


func _scene_y(f: Fight) -> float:
	# The engine's y is the TOP of the box and grows DOWNWARD, so the height
	# above the floor is the floor minus where the feet are.
	#
	# No correction for where the model's feet sit: the skinned character's
	# lowest vertex is at -3.9 and Graveyard's cobbles are a plane at exactly
	# y = 0, so the model already stands on the floor at the origin.
	return float(_ground_y() - f.yi()) * scale_units


## How far past the last logic tick the frame being DRAWN sits, 0..1. Set by
## the process loop from its own accumulator, and used for nothing the fight
## decides -- no hit, no distance, no timer reads it. It is purely what the
## eye gets between two ticks of a simulation that runs at a fixed rate.
var render_alpha := 0.0


func _place() -> void:
	var a := clampf(render_alpha, 0.0, 1.0)
	for f in fighters:
		if not frozen:
			_pose(f)
		# **The simulation is 60 Hz; the drawing is not.** `tick()` advances
		# the fight at a fixed rate whatever the monitor runs at, and that
		# was always right -- the fight is identical at 60 fps and at 144.
		# What was missing is that this drew the latest tick and nothing
		# else, so the extra frames of a fast screen showed the same pose
		# twice. Drawing the point between the previous tick and this one is
		# what turns them into motion.
		var px := float(f.prev_x) + (float(f.x) - float(f.prev_x)) * a
		var py := float(f.prev_y) + (float(f.y) - float(f.prev_y)) * a
		f.node.position = Vector3(
			px / float(ONE) * scale_units,
			(float(_ground_y()) - py / float(ONE)) * scale_units,
			0.0)
		f.node.set_facing(f.facing)
		_place_spear(f)
	if blood:
		blood.draw(scale_units, float(FLOOR_Y))


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


## **The camera is the engine's, not a framing.**
##
## It used to be a distance derived from the fighter's height with a widening
## term for the gap -- invented, and it showed: the pair drifted in and out as
## they moved. The binary has the real thing, in two numbers that agree with
## each other:
##
##     init_players        G[0xb4] = RoundParam[1] - 399     the rightmost x
##     t_sctele_calla_1    clamps to G[0x468] .. G[0x468] + 399
##
## **399 units wide, sliding between -550 and 950.** And that width is not
## arbitrary either: `repell_func` leashes the two fighters at 304 units apart,
## and 304 plus a 55-wide body either side is 414 -- near enough that the view
## is built around the leash. The two always fit, so the camera never has to
## widen and never has to choose whom to follow.
##
## The one thing this adds is what to do with a window wider than the original
## 3:2. Cropping the top off would be the literal reading and would be worse to
## play; instead the VERTICAL span is held at the original's 399/1.5 and the
## extra aspect becomes extra width. That is the ordinary widescreen rule and
## it is stated rather than hidden.
const CAM_ASPECT := 1.5                  ## the original's 480x320 screen
const CAM_TAN_HALF_FOV := 0.2217         ## this camera's own


func _frame_camera() -> void:
	if _cam == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)

	# Hold the vertical span the original shows, so a wide window gains width
	# instead of losing height.
	var span_v := float(CAM_WIDTH) / CAM_ASPECT * scale_units
	var dist := span_v / (2.0 * CAM_TAN_HALF_FOV)
	var span_h := span_v * aspect / scale_units          # in engine units

	# The window slides between the two RoundParam edges, and its centre
	# follows the midpoint of the pair -- which always fits, because the leash
	# never lets them past 304 apart.
	# **The camera does not follow a teleporting fighter.** In the engine
	# `tl_do_scorp_tele` spawns `t_s_t_scroller` to drive the scroll for the
	# duration and calls `sans_repell_3`, so the view stops tracking him --
	# and it has to, because the wrap is measured against the view's own edge.
	# Letting the midpoint chase him moved that edge away as fast as he flew at
	# it, and the wrap never fired.
	if _teleporting():
		return
	var mid := float(fighters[0].xi() + fighters[1].xi()) * 0.5
	var half := span_h * 0.5
	var lo := float(ROUNDPARAM_LEFT) + half
	var hi := float(ROUNDPARAM_RIGHT) - half
	if lo > hi:
		# A window wider than the whole arena: centre it rather than clamp to
		# nothing.
		mid = float(ROUNDPARAM_LEFT + ROUNDPARAM_RIGHT) * 0.5
	else:
		mid = clampf(mid, lo, hi)

	cam_mid = int(mid)
	cam_span = span_h
	# The shake, while one is running: it decays over its eight frames and
	# alternates side to side, which is what a two-halfword amplitude of {6, 6}
	# reads as on a camera that has no shake parameter of its own.
	var jx := 0.0
	var jy := 0.0
	if shake > 0:
		var k := shake_amp * float(shake) / float(SHAKE_FRAMES) * scale_units
		jx = k if (shake & 1) == 0 else -k
		jy = k * 0.5 if (shake & 2) == 0 else -k * 0.5
	_cam.position = Vector3(mid * scale_units + jx,
		height * 0.66 + jy, dist)
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
	# Whatever is left over is how far past the last tick this drawn frame is.
	render_alpha = float(_accum / step) if step > 0.0 else 0.0
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
		if f.sp_live and not f.sp_stuck:
			var pb := _spear_box(f)
			r.mesh = _wire_box(
				float(pb[0]) * scale_units, float(FLOOR_Y - pb[3]) * scale_units,
				float(pb[2]) * scale_units, float(FLOOR_Y - pb[1]) * scale_units,
				Color(1.0, 0.25, 0.2))
			r.visible = true
			continue
		var stk := _strike_of(f, fighters[1 - i])
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


## What this fighter's attack actually resolved to -- the roundhouse, not the
## high kick that asked for it.
func _attack_name(f: Fight, which: int) -> String:
	if f.st != St.ATTACK:
		return ""
	var id := f.strike
	return _Stk.NAME[id] if id >= 0 else MOVE_NAME[f.move]


## One line per fighter, for the HUD.
func status() -> String:
	var names := ["STANCE", "WALK-F", "WALK-B", "DUCK", "BLOCK", "JUMP",
		"ATTACK", "HIT", "SPECIAL", "SPEARED", "THROWN", "FALLING", "DOWN",
		"GETUP", "DEAD", "VICTORY", "STUNNED", "UNBLOCK", "RUN"]
	var out := "%d fps   pose %.1f ms   tick %d
" % [
		Engine.get_frames_per_second(),
		(fighters[0].node.pose_usec + fighters[1].node.pose_usec) / 1000.0,
		frame]
	for i in fighters.size():
		var f := fighters[i]
		out += "P%d %3d hp  %-7s %-11s  x %5d  y %5d  %s\n" % [
			i + 1, f.health, names[f.st],
			f.special_name if f.st == St.SPECIAL else _attack_name(f, i),
			f.xi(), f.yi(), "->" if f.facing > 0 else "<-"]
	return out
