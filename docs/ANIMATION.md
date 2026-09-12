# Animation — streams, parts and rates

[← README](../README.md) · [Fight system](FIGHT-SYSTEM.md)

The single most productive thing understood in this project, and the source of
two separate bugs that each looked like a modelling problem.

---

## Where a character's animations live

```
_character_anitabs1  0x0016ee34   indexed by character number
  -> _nj_ani_data    0x0015978c   Scorpion (18) and the other five ninjas
       first 0x170 bytes = 92 pointers, one per animation
       each points at a STREAM
```

All six ninjas share `_nj_ani_data`, which is the check that it is the right
table.

A stream is a list of 32-bit words that `do_next_a9_frame_pxob` `0x00059c74`
walks. A word above `0x12` is a **frame number** and the interpreter returns —
one displayed frame, one tick of the animation clock. Words at or below `0x12`
are opcodes: 0 ends a part, 1 jumps (which is how a clip loops), 2 flips the
fighter, 5 marks a last frame, 13 is a frame that costs no time, and the rest
are sounds, offsets, calls and a per-character branch.

The frame numbers are **global** ids. `framelists/SCORPIONFRAMES.bin` maps them
to Scorpion's own frames — 7,139 slots, `0xFFFF` where he does not have that
animation — and `scorpionframes.txt` names them.

---

## Streams have parts, separated by a zero

`find_part2` `0x00055450` is four instructions:

```c
p = pl->0x40;
do { w = *p++; pl->0x1c = w; } while (w != 0);
pl->0x40 = p;
```

Walk forward until a word reads zero, and leave the pointer just past it. And
`next_anirate` `0x0005a680` **stops** when the next word is zero: the animation
holds there until some state calls `find_part2`.

So a stream is not one list. It is parts, and almost every clip has two.

```
animation 30, SCKNOCKDOWN, raw:

    253 255 257 258 259 261   0   263 265   0
    \_______ the tumble ______/   \_ flat _/

    through SCORPIONFRAMES.bin:  119..124   |   125, 126
```

**This is why two different things looked broken.**

A generator that stops at the first zero — the very marker `find_part2` looks
for — produces a table where every clip is missing its second half. That
generator wrote `umk3_scorpion_ani.gd`, and for a long time this project had:

- **attacks with no retraction.** The low punch stopped on frame 138 with the
  arm fully extended and snapped back to the stance, which reads as a broken
  model rather than a missing frame.
- **knockdowns that never reached the ground.** The fighter ended his tumble
  propped half up, because the two frames that lay him flat were in part two.

A note in that generated file claiming frames 125 and 126 "appear in no stream"
was an artefact of the same bug and was simply wrong.

---

## Part two of an attack is the retraction

`t_retract_strike` `0x0004cb48` clears the tag with `pl->0x20 = 0` and hands to
`t_retract_strike_act` `0x0004cadc`, which pushes `t_act_mframew`. Neither
touches `pl->0x40` or the rate — so the stream carries straight on from where
the swing left it, at the same speed. The naming confirms it:
`t_joy_un_hi_punch1` is the *un*-punch.

```
SCHIPUNCH     80  81  82  |  83  84  85     a separate return
SCLOPUNCH    136 137 138  | 139 140 141
SCHIKICK      74 .. 79    |  78 77 76 75 74 the same frames, backwards
SCLOKICK     130 ..135    | 134 133 ..130
SCSPINHOOK   208 ..212    | 213 214 215
SCSWEEPKICK  252 ..256    | 257 258 259
SCUPPERCUT   271 ..275    | 274             one frame, a settle
SCDUCKPUNCH   36  37  38  |  37  36  22
SCDUCKHIKICK  26 .. 29    |  28  27  26 22
SCDUCKLOKICK  33  34  35  |  34  34  22
```

The three ducking attacks end on frame **22**, which is the ducking pose: they
return to a crouch rather than to standing. Nobody would have guessed that.

---

## Part two of a knockdown is the landing

`t_reaction_land` `0x000425b8` runs for anything that came down from a flight:

```
shake_n_sound            shake {6,6} and rsnd 13, the ground thud
pl->0x40 = 30            the same animation it was already playing
find_ani_part2           get_char_ani, then skip to part two
pl->0x1c = 4             rate 4
t_mframew, wait 3, then the getup
```

Same clip, second part, and it holds its last frame. The getup (animation 33)
even carries the *sweep fall's* frames as its own part two.

---

## Every move has its own rate

`init_anirate` `0x000553a0` writes `part->0x1c = pl->0x1c` and starts the
countdown at 1, so the first advance lands on the very next frame.
`next_anirate` decrements it and reloads.

Each attack proc sets its own rate before handing off — the same four-line
shape the block and the run use:

| move | animation | rate | tag |
|---|---|---|---|
| high kick | 17 SCHIKICK | 1 | `0x103` |
| low kick | 18 SCLOKICK | 1 | `0x104` |
| sweep | 20 SCSWEEPKICK | 3 | `0x10d` |
| roundhouse | 21 SCSPINHOOK | `_round_speeds[char]` = 3 | `0x105` |
| uppercut | 11 SCUPPERCUT | 2 | `0x10e` |
| duck punch | 8 | 3 | `0x108` |
| duck kick h | 9 | 3 | `0x106` |
| duck kick l | 10 | 2 | `0x107` |
| knee | 19 SCKNEECOMBO | 1 | `0x109` |
| elbow | `_ochar_elbow_animations[char]` = 16 SCCOMBO | 1 | `0x10a` |
| jump-up punch | 24 | 9 | |
| jump-up kick | 23 | 10 | |
| flip punch | 24 | 12 | |
| flip kick | 25 | 11 | |
| block | 12 (6 ducking) | 3 | `0x700` / `0x701` |
| run | 70 SCRUN | 3 | |
| knockdown landing | 30, part two | 4 | |

Two of those are per-character byte tables rather than constants:
`_round_speeds` `0x001673b0` and `_ochar_elbow_animations` `0x001664bc`, both
byte 18 for Scorpion. The top bit of an elbow entry is a "this character has no
elbow" flag, and he does not carry it.

**The punches are the exception, and it is a finding rather than a gap.**
`t_joy_hi_punch` and `t_joy_un_hi_punch1` set the animation and go to
`find_ani_part2` without touching the rate at all, so a jab runs at whatever
the fighter was already carrying — 6 from a stance, since `stance_setup`
`0x000553c4` installs that.

The air attacks' long rates are not slowness: 3 frames at 12 is 36 game frames,
which is how long the jump lasts. The pose is held through the arc.
