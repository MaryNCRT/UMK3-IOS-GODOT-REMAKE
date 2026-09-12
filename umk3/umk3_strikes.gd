## The ninjas' attack boxes, out of the binary's own table.
##
## GENERATED, not transcribed. `get_char_stk` (0x00055f88) indexes
## `_strike_tables` (0x00169fbc) by the character number and then by a STRIKE
## ID; Scorpion is 18 and lands on `_nj_strikes` (0x00169f50), which is the
## array below in the order it is stored. He shares it with the other five
## ninjas, which is the check that it is the right table.
##
## ## The seven words, and what the engine does with four of them
##
## `strike_check_ptr` (0x00059424) walks words 0..3 into the object's 0x20,
## 0x24, 0x28 and 0x2c, and `strike_check_regs` (0x00059280) turns those into a
## rectangle. **Reading that function is the only way to get the box right, and
## it does not say what a reader expects:**
##
##     if (word0 & 0x8000) word0 |= 0xffff0000;   16-bit, sign extended
##     if (word1 & 0x8000) word1 |= 0xffff0000;
##
##     facing RIGHT (the part's 0x28 bit 4 CLEAR)
##         left  = X + word0 - word2
##     facing LEFT  (bit 4 set)
##         left  = X - word0
##     right = left + word2
##     top    = Y + word1
##     bottom = top + word3
##
## So **word0 is the distance to the FAR edge and word2 is the width measured
## BACK toward the fighter.** A high kick with x = 96 and w = 65 covers
## `X+31 .. X+96`, not `X+96 .. X+161`. This port had it the second way, which
## put every box a full width too far out -- the low kick, 74 wide, reached to
## X+183 instead of X+109, and that is the one that looked most broken.
##
## The sign extension is not decoration either: the uppercut's word1 is stored
## as 65517, which is -19 as a 16-bit value, and it is the only record with a
## box that starts above the fighter's own origin.
##
## Word 5's second byte is the DAMAGE -- jab 11, low punch 8, low kick 21, high
## kick 24, roundhouse 29, uppercut 36, which is Mortal Kombat's own order out
## of a table nobody here wrote. Word 6 is the level, and it is 1 for
## everything except the sweep.
##
## ## No game data ships here
##
## These are numbers recovered from the binary, like the button tables and the
## animation streams. The game's files are not in this repository.
class_name UMK3Strikes
extends RefCounted

const X := 0
const Y := 1
const W := 2
const H := 3
const DMG := 4
const LEVEL := 5
const REACT := 6

## The strike ids, by the name on the record.
enum {
	HIKICK, LOKICK, HI_PUNCH, LO_PUNCH, SWEEP, DUCK_PUNCH, DUCK_KICKH,
	DUCK_KICKL, UPPERCUT, JUMP_PUNCH, JUMP_KICK, FLIP_KICK, FLIP_PUNCH,
	ROUNDH, KNEE, ELBOW, SLIDE, ORB, SPIT, SZ_FORWARD_ZAP, SCORP_SPEAR,
	REPTILE_DASH, REPTILE_DASH2, SCORP_TELE, FLOOR_ICE, ERMAC_ZAP, ERMAC_SLAM,
}

const NAME := ["hikick", "lokick", "hi punch", "lo punch", "sweep",
	"duck punch", "duck kick h", "duck kick l", "uppercut", "jump punch",
	"jump kick", "flip kick", "flip punch", "roundhouse", "knee", "elbow",
	"slide", "orb", "spit", "sz forward zap", "spear", "reptile dash",
	"reptile dash 2", "teleport punch", "floor ice", "ermac zap",
	"ermac slam"]

## x, y, w, h, damage, level, reaction -- in the table's own order, which is
## the strike id.
const STK := [
	[96, 4, 65, 44, 24, 1, 0],         #  0  hikick          -> t_r_hi_kick
	[109, 42, 74, 19, 21, 1, 1],       #  1  lokick          -> t_r_lo_kick
	[77, 1, 53, 33, 11, 1, 2],         #  2  hi_punch        -> t_r_hi_punch
	[84, 31, 61, 20, 8, 1, 3],         #  3  lo_punch        -> t_r_lo_punch
	[103, 107, 81, 27, 20, 2, 4],      #  4  sweep           -> t_r_sweep
	[77, 54, 54, 18, 6, 1, 5],         #  5  duck_punch      -> t_r_duck_punch
	[72, 59, 65, 30, 12, 1, 6],        #  6  duck_kickh      -> t_r_duck_kickh
	[87, 105, 68, 22, 6, 1, 7],        #  7  duck_kickl      -> t_r_duck_kickl
	[77, -19, 58, 74, 36, 1, 8],       #  8  uppercut        -> t_r_uppercut
	[78, 23, 58, 46, 16, 1, 11],       #  9  jump_punch      -> t_r_flip_punch
	[78, 2, 66, 59, 19, 1, 11],        # 10  jump_kick       -> t_r_flip_punch
	[66, 35, 46, 38, 26, 1, 10],       # 11  flip_kick       -> t_r_flip_kick
	[78, 23, 58, 46, 16, 1, 11],       # 12  flip_punch      -> t_r_flip_punch
	[91, 0, 70, 54, 29, 1, 12],        # 13  roundh          -> t_r_roundhouse
	[74, 33, 49, 52, 18, 1, 9],        # 14  knee            -> t_r_elbow_knee
	[89, 15, 60, 44, 16, 1, 76],       # 15  elbow           -> t_r_tusk_elbow
	[56, 89, 71, 42, 13, 1, 45],       # 16  slide           -> t_r_slide
	[99, 44, 47, 61, 18, 1, 113],      # 17  orb             -> t_r_orb
	[193, 27, 64, 12, 15, 1, 114],     # 18  spit            -> t_r_spit
	[130, -11, 62, 6, 0, 1, 44],       # 19  sz_forward_zap  -> t_r_freeze
	[0, 0, 22, 22, 8, 1, 117],         # 20  scorp_spear     -> t_r_scorpion_spear
	[43, 9, 34, 110, 0, 1, 116],       # 21  reptile_dash    -> t_r_reptile_dash
	[68, 11, 39, 60, 13, 1, 36],       # 22  reptile_dash2   -> t_r_jax_dash
	[76, 17, 54, 42, 15, 1, 115],      # 23  scorp_tele      -> t_r_scorp_tele
	[154, 118, 78, 17, 0, 1, 118],     # 24  floor_ice       -> t_r_floor_ice
	[109, 58, 34, 9, 20, 1, 119],      # 25  ermac_zap       -> t_r_ermac_zap
	[206, 36, 106, 90, 0, 1, 120],     # 26  ermac_slam      -> t_r_ermac_slam
]

## **The block half of every record, which this port did not have at all.**
##
## `strike_check_regs` splits word 4 into TWO bytes and word 5 into two more:
##
##     word4 >> 8   the reaction, into `_reaction_table`      (121 procs)
##     word4 & 0xff the BLOCK reaction, into `_block_xfers`   (24 procs)
##     word5 >> 8   the damage a clean hit does
##     word5 & 0xff the CHIP damage a blocked hit still does
##
## I had read the low byte of word 4 as "flags" and never read the low byte of
## word 5 at all. They are neither: 0x1805 on the high kick is block reaction 6
## and five points of chip.
const CHIP := [5, 4, 3, 2, 3, 2, 3, 2, 9, 5, 6, 7, 5, 4, 3, 3,
	3, 2, 4, 0, 2, 0, 3, 4, 0, 3, 0]

## Which of the 24 `_block_xfers` procs the victim goes into when he blocks it.
const BLOCK_IDX := [6, 6, 17, 23, 3, 10, 11, 10, 2, 1, 1, 1, 1, 1, 7, 7,
	0, 1, 1, 5, 0, 0, 0, 0, 22, 1, 1]

## Which of the two block noises that proc makes: `rsnd_func(pl, 5)` is
## `_tab_rsnd_big_block` and `rsnd_func(pl, 6)` is `_tab_rsnd_small_block`,
## read off the first call in each of the 24 procs. Eleven of them make no
## noise of their own at all, and that silence is the measurement too.
const BLOCK_BIG := [1, 2, 6, 7, 11, 15, 18]
const BLOCK_SMALL := [0, 3, 10, 16, 17, 23]

## `is_he_blocking` (0x0005837c) tests the LEVEL against this, and nothing
## else: `if (level & 2) he is not blocking` -- unless he is holding down, in
## which case he is duck-blocking and it is stopped anyway. The sweep is the
## only record in the table with the bit set.
const LVL_LOW := 2

## **How hard each reaction pushes the victim back, measured.**
##
## The fifth word of a strike record is `(reaction << 8) | flags`, and the
## reaction indexes `_reaction_table` (0x00166fc0) -- 121 pointers to the
## `t_r_*` procs in mkreact.c. Every one of the 27 ids above lands on a proc
## whose NAME matches the strike, which is what proves the reading: the spear's
## 0x7500 is `t_r_scorpion_spear` and the teleport's 0x7300 is `t_r_scorp_tele`.
##
## Scanning all 64 call sites of `away_x_vel` (0x00055ab0) for the 16.16
## literal each reaction loads gives the knockback directly:
##
##     hi kick 4.5   low kick 4.0   duck kick h 4.5   duck kick l 3.0
##     duck punch 4.0   flip punch 1.0   slide 3.0
##
## **And the ones that are missing are the finding.** `t_r_hi_punch`,
## `t_r_lo_punch`, `t_r_uppercut`, `t_r_roundhouse` and `t_r_sweep` never call
## it: a jab does not push you, an uppercut launches you upward, and a sweep
## and a roundhouse knock you down rather than back. This port had one invented
## number for all of them and doubled it above 24 damage.
const REACT_VX := {
	0: 4.5,      # t_r_hi_kick
	1: 4.0,      # t_r_lo_kick
	5: 4.0,      # t_r_duck_punch
	6: 4.5,      # t_r_duck_kickh
	7: 3.0,      # t_r_duck_kickl
	11: 1.0,     # t_r_flip_punch
	45: 3.0,     # t_r_slide
}

## **The engine's own close-range thresholds**, both measured as the
## centre-to-centre distance `get_x_dist` (0x0002f3a0) computes:
##
##     t_knee_check  (0x0002f9d4)   0x4a   a kick inside 74 becomes a KNEE
##     t_elbow_check (0x0002f8ac)   0x4a   a high punch inside 74 is an ELBOW
##
## And `is_stick_away` (0x00055df0) decides the other pair: holding back turns
## the high kick into a ROUNDHOUSE (`t_joy_hi_kick` -> `t_joy_roundhouse`) and
## the low kick into a SWEEP (`t_joy_lo_kick` -> `t_joy_sweep_kick`).
##
## That is six different attacks off two buttons, which is what a Mortal Kombat
## normal set is, and the fight had none of it.
const CLOSE := 0x4a
