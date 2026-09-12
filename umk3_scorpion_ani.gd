## Scorpion's animations, decoded from the engine's own streams.
##
## GENERATED, not transcribed. `_character_anitabs1` (0x0016ee34) indexes by
## character number into a per-character table of animation pointers; Scorpion
## is 18 and lands on `_nj_ani_data` (0x0015978c) -- **which he shares with
## Reptile, Ermac, classic Sub-Zero, classic Smoke and Noob Saibot**, all six
## ninjas, and that is the check that the table is the right one. Its first
## 0x170 bytes are 92 pointers; each points at a stream that
## `do_next_a9_frame_pxob` (0x00059c74) walks:
##
##     a word above 0x12 is a FRAME and the interpreter returns -- one displayed
##     frame, one tick of the animation clock
##     0 ends the animation, 1 jumps (which is how a clip loops), 2 flips the
##     fighter, 5 is the last frame, 13 is a frame that costs no time, and the
##     rest are sounds, offsets, calls and a per-character branch
##
## The frame numbers in the stream are GLOBAL ids. `framelists/SCORPIONFRAMES.bin`
## maps those to Scorpion's own frames -- 7,245 slots, 0xFFFF where a character
## does not have that animation -- and `scorpionframes.txt` names them. Stance
## comes out 216..224 and the walk 282..290, which is exactly what had been
## transcribed BY HAND from the names; what the hand missed is everything else.
##
## ## What the hand got wrong
##
## **The streams are not ranges.** `SCHIHIT` is 72, 73, 72, 71 -- it goes back.
## `SCDUCKHIT` is 31, 32, 31, 30. A range plays those as 71, 72, 73 and the
## motion reverses.
##
## **`SCHIPUNCH` is three frames, not seven.** 80, 81, 82. The hand-read range
## 80..86 swept in four frames that belong to something else entirely.
##
## **The backward walk is the forward walk REVERSED**, 290 down to 282, not the
## same cycle played forwards.
##
## **There are two jump flips**, 26 and 27, one each way round.
##
## ## No game data ships here
##
## These are frame NUMBERS recovered from the binary, the same kind of thing as
## the button tables and the sound groups. The frames themselves are in the
## user's own `.skinanim`.
class_name UMK3ScorpionAni
extends RefCounted

## id -> [name, loops, [frame, ...]]
const ANI := [
	["SCSTANCE", true, [216, 217, 218, 219, 220, 221, 222, 223, 224]],  # 0
	["SCWALK", true, [282, 283, 284, 285, 286, 287, 288, 289, 290]],  # 1
	["SCWALK", true, [290, 289, 288, 287, 286, 285, 284, 283, 282]],  # 2
	["SCTURN", false, [269, 270, 269]],  # 3
	["SCDUCK", false, [20, 21, 22]],  # 4
	["SCDUCKTURN", false, [39, 40, 39, 22]],  # 5
	["SCDUCKBLOCK", false, [23, 24, 25]],  # 6
	["SCDUCKHIT", false, [31, 32, 31, 30]],  # 7
	["SCDUCKPUNCH", false, [36, 37, 38]],  # 8
	["SCDUCKHIKICK", false, [26, 27, 28, 29]],  # 9
	["SCDUCKLOKICK", false, [33, 34, 35]],  # 10
	["SCUPPERCUT", false, [271, 272, 273, 274, 275]],  # 11
	["SCBLOCK", false, [1, 2, 3]],  # 12
	["SCVICTORY", false, [276, 277, 278, 279, 280, 281]],  # 13
	["SCHIPUNCH", false, [80, 81, 82]],  # 14
	["SCLOPUNCH", false, [136, 137, 138]],  # 15
	["SCCOMBO", false, [8, 9, 10, 11]],  # 16
	["SCHIKICK", false, [74, 75, 76, 77, 78, 79]],  # 17
	["SCLOKICK", false, [130, 131, 132, 133, 134, 135]],  # 18
	["SCKNEECOMBO", false, [108, 109, 110]],  # 19
	["SCSWEEPKICK", false, [252, 253, 254, 255, 256]],  # 20
	["SCSPINHOOK", false, [208, 209, 210, 211, 212]],  # 21
	["SCJUMP", false, [94, 95, 96]],  # 22
	["SCJUMPKICK", false, [105, 106, 107]],  # 23
	["SCFLIPUNCH", false, [62, 63, 64]],  # 24
	["SCFLIPKICK", false, [54, 55, 56]],  # 25
	["SCJUMPFLIP", true, [97, 98, 99, 100, 101, 102, 103, 104]],  # 26
	["SCJUMPFLIP", true, [97, 104, 103, 102, 101, 100, 99, 98]],  # 27
	["SCHIHIT", false, [72, 73, 72, 71]],  # 28
	["SCLOHIT", false, [128, 129, 128, 127]],  # 29
	["SCKNOCKDOWN", false, [119, 120, 121, 122, 123, 124]],  # 30
	["SCSWEEPFALL", false, [246, 247, 248, 249]],  # 31
	["SCSTUMBLE", false, [225, 226, 227, 228, 229, 230, 231, 232]],  # 32
	["SCGETUP", false, [65, 66, 67, 68, 69, 70]],  # 33
	["SCSWEEPUP", false, [260, 261, 262, 263, 264, 265]],  # 34
	["SCFLIP", false, [46, 47]],  # 35
	["SCSTANCE", true, [216, 217, 218, 219, 220, 221, 222, 223, 224]],  # 36
	["SCSTUNNED", true, [233, 234, 235, 236, 237, 238, 239, 240]],  # 37
	["SCFLIPPED", false, [57, 58, 59]],  # 38
	["SCFLIPPED", false, [57, 58, 59, 60, 60]],  # 39
	["SCFLIPPED", false, [57, 58, 59, 60, 60, 124]],  # 40
	["SCFLIPPED", false, [57, 58, 59, 60, 124, 124]],  # 41
	["SCFLIPPED", false, [57, 61, 61, 123, 123, 123]],  # 42
	["SCFLIPPED", false, [57, 58, 59, 60, 124]],  # 43
	["SCSTUMBLE", false, [225, 226, 57, 57, 57, 57, 60, 125]],  # 44
	["SCFLIPPED", false, [57, 58, 58, 59, 60, 60, 61, 125]],  # 45
	["SCSTUMBLE", false, [225, 57, 58, 59, 60, 61, 125]],  # 46
	["SCSTUMBLE", false, [225, 225, 57, 58, 59, 60, 61, 61, 61, 61]],  # 47
	["SCFLIPPED", false, [57, 58, 59, 60, 61, 61, 124, 57, 58, 59, 61, 124]],  # 48
	["SCFLIPPED", false, [57, 58, 59, 59, 59, 125]],  # 49
	["SCFLIPPED", false, [57, 57, 58, 59, 60, 124, 124, 124, 57, 57, 58, 60, 61, 124]],  # 50
	["SCFLIPPED", false, [57, 57, 58, 59, 60, 60]],  # 51
	["SCFLIPPED", false, [58, 59, 60, 60, 124, 124]],  # 52
	["SCFLIPPED", false, [57, 58, 59, 60]],  # 53
	["SCKNOCKDOWN", false, [119, 57, 58, 58, 59, 60, 61]],  # 54
	["SCFLIPPED", false, [57, 57, 58, 59, 60]],  # 55
	["SCFLIPPED", false, [57, 57, 58, 59, 59, 60]],  # 56
	["SCFLIPPED", false, [57, 57, 58, 59, 59, 60]],  # 57
	["SCFLIPPED", false, [57, 57, 58, 59, 59, 60]],  # 58
	["SCFLIPPED", false, [57, 57, 58, 59, 59, 60]],  # 59
	["SCSTANCE", true, [216, 217, 218, 219, 220, 221, 222, 223, 224]],  # 60
	["SCKNOCKDOWN", false, [119, 121, 122]],  # 61
	["SCKNOCKDOWN", false, [119, 57, 59, 60, 61]],  # 62
	["SCSTANCE", true, [216, 217, 218, 219, 220, 221, 222, 223, 224]],  # 63
	["SCSTUMBLE", false, [226, 226, 226]],  # 64
	["SCFLIPPED", false, [58, 59, 60, 60, 124, 124]],  # 65
	["SCKNOCKDOWN", false, [121, 122, 123, 123, 57, 59]],  # 66
	["SCFLIPPED", false, [57, 58, 59, 60, 61]],  # 67
	["SCFLIPPED", true, [57, 225, 120, 225]],  # 68
	[],  # 69 -- frames this character does not have
	["SCRUN", true, [174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185]],  # 70
	["SCFALLTHUD", false, [41, 42, 43, 44, 45]],  # 71
	["SCSCARED", false, [186]],  # 72
	[],  # 73 -- frames this character does not have
	[],  # 74 -- frames this character does not have
	[],  # 75 -- frames this character does not have
	["SCCOMBO", false, [16, 17, 18]],  # 76
	["SCUPPERCUT", false, [271, 272, 273, 274, 275]],  # 77
	[],  # 78 -- frames this character does not have
	[],  # 79 -- frames this character does not have
	[],  # 80 -- frames this character does not have
	["SCFLIPUNCH", false, [62, 63, 266]],  # 81
	["SCSPEAR", false, [199, 200, 201, 202]],  # 82
	["SCFLIP", false, [46, 47]],  # 83
	["SCCOMBO", false, [16, 17, 18]],  # 84
	["SCSUMMON", false, [241, 242, 243, 244, 245]],  # 85
	["SCMASKOFF", false, [142, 143, 144, 145, 146, 147]],  # 86
	[],  # 87 -- frames this character does not have
	["SCORPFIRE", false, [160, 161, 162]],  # 88
	[],  # 89 -- frames this character does not have
	[],  # 90 -- frames this character does not have
	["SCSPINHOOK", false, [208, 209, 210, 211, 212]],  # 91
]
