# Methodology — what "1:1" means here

[← README](../README.md)

This page is the one to read before changing anything in `umk3/umk3_fight.gd`.
It is not a style guide. It is the reason the numbers in that file can be
trusted, and the rule that keeps them trustworthy.

---

## The rule

> **Read the whole function, follow the chain to the leaf, and measure.
> Never infer from plausibility.**

A remake can be built two ways. You can play the original, form an opinion
about how far an uppercut throws somebody, and tune a number until it looks
right. Or you can find the instruction that sets that number and write down
what it says.

The first is faster and produces something that feels approximately correct
forever. The second is slower, and produces something that is either right or
demonstrably wrong — which is a much more useful state to be in, because wrong
can be fixed by reading further.

This project does the second. Concretely, for any behaviour:

1. **Find the symbol.** The retail binary kept its STABS table: 29,076 symbols,
   4,342 named functions. The uppercut's launch is not "somewhere in the
   physics" — it is `t_rup3`, and it is at `0x00045ed4`.
2. **Disassemble the whole function.** Not the first ten instructions, not the
   part that looks relevant. The whole thing, including the branches you think
   you do not need.
3. **Follow the chain.** Almost nothing interesting is in the function you
   first look at. `t_r_uppercut` does not launch anybody; it pushes
   `t_reaction_start`, which calls `reaction_start_chores`, which tail-calls
   `t_rst5`. The launch is in a *different* branch — `t_rup3` — and the numbers
   it sets are consumed one level further down in `t_flight_call`.
4. **Resolve the indirections.** This binary is Thumb-2 and almost every
   constant is pc-relative. A `ldr r3, [pc, #0x98]` followed by `add r3, pc`
   is an address you have to compute; if it lands in `__nl_symbol_ptr` between
   `0xf301c` and `0xf38cc` it is a GOT slot and the real target is one more
   dereference away. Several of the most important findings in this project
   were behind exactly that pattern.
5. **Write the number down with its address**, so the next person can check it
   without repeating the search.

---

## The three kinds of constant

Every value in the fight code is labelled, and the label matters more than the
value:

| Label | Means | Example |
|---|---|---|
| **measured** | Read out of the binary. The comment carries the address. | `const UPCUT_VY := -int(18.0 * ONE)  ## measured, 0xffee0000` |
| **chosen** | No measurement exists yet. Somebody picked it, and the comment says so. | the blood particles' spread and lifetime |
| **generated** | Emitted from the binary's own data by a script. Not hand-edited. | `umk3_strikes.gd`, `umk3_scorpion_ani.gd` |

A file that is **generated** says GENERATED in its header. If you find yourself
hand-editing one, that is the signal that the generator is wrong, not the file.

The point of the third category, **chosen**, is that it is visible. A remake
full of tuned numbers with no labels is impossible to improve, because nobody
can tell which numbers are load-bearing. Here you can grep for the word.

---

## Where the two repositories meet

The [decompilation](https://github.com/MaryNCRT/Ultimate-Mortal-Kombat-3-iOS-Recomp)
and this remake are the same investigation with two outputs.

- A **fact about the binary** — a hitbox formula, a table of per-character
  animation rates, the layout of a joystick word — belongs to both. It is
  written as C in one and as GDScript in the other, and the hex address in the
  comment is the same in both.
- A **transcription** belongs only to the decompilation. This project never
  copies C structure; it copies *conclusions*.
- An **engine decision** — how the camera interpolates, how the window resizes,
  what a pause menu looks like — belongs only here, and is marked as this
  project's own rather than the original's.

That is why the remake can use Godot's renderer without any loss of fidelity:
the renderer was never carrying any of the fidelity in the first place. The
fidelity lives in the numbers.

---

## Mistakes this method caught

These are worth listing because each one looked obviously right at the time,
and none of them would have been caught by playing the game and squinting.

**The strike box was a full width too far out.** The obvious reading of a
record holding `x`, `y`, `w`, `h` is a rectangle at `X + x` extending `w` to
the right. `strike_check_regs` (`0x00059280`) says otherwise: facing right,
`left = X + x - w`. So `x` is the distance to the *far* edge and `w` is
measured back toward the fighter. A low kick with `x = 109, w = 74` covers
`X+35 .. X+109`, not `X+109 .. X+183`. Every attack in the game had been
reaching half a body too far.

**Blocking did nothing at all.** It was started from the button's press edge,
like every other move. `check_block_bit` (`0x0002eca8`) is a *level* test, and
`is_he_blocking` (`0x0005837c`) polls it again at the instant of the hit — so a
held block lasted two frames and was never down when a hit arrived. Nothing on
screen looked wrong; the block animation played perfectly. It simply never
blocked.

**The strike records had a whole half nobody had read.** Word 4 is not
`(reaction << 8) | flags`; the low byte is an index into `_block_xfers`, a
table of 24 procs. Word 5 is not just damage; its low byte is the chip damage a
blocked hit still does. Two columns of the table had been sitting there unread.

**The fall was missing its ending.** `find_part2` (`0x00055450`) is four
instructions: walk the animation stream forward until a word reads zero and
leave the pointer past it. Streams are *parts separated by a zero*. The
generator that built the animation table stopped at the first zero — the very
marker that function looks for — so every clip in the game was missing its
second half. Attacks had no retraction and knockdowns never reached the ground.
A note in the generated file claiming those frames "appear in no stream" was an
artefact of the bug, and was wrong.

**Every attack has its own speed.** The port played all of them at the stance's
inherited rate of 6. Each `t_stat_do_*` proc sets its own: the high kick is
rate 1, the uppercut 2, the sweep 3, and the roundhouse comes from a
per-character byte table, `_round_speeds`. A six-frame kick was taking
thirty-six game frames instead of six.

**The pause menu paused nothing.** Not a binary matter at all, but the same
discipline caught it: `PROCESS_MODE_ALWAYS` on the shell propagates down
through every child left on inherit, which was the entire 3D world.

---

## The tools

Small and in the [other repository](https://github.com/MaryNCRT/Ultimate-Mortal-Kombat-3-iOS-Recomp),
under `tools/` and `OUTPUT/tools/`:

| Tool | Does |
|---|---|
| `macho.py` | Parses the Mach-O, the symbol table and the indirect symbol table |
| `disasm.py` | Disassembles one function by name, ARM or Thumb, with call targets named |
| `pcref.py` | Resolves every pc-relative literal in a function to a symbol, including GOT slots |
| `callers.py` | Finds every `bl` that targets a given function |
| `dump.py` | Dumps a data symbol as words, naming any that look like addresses |

One trap is worth repeating because it invalidates everything if missed:
**this binary does not mark Thumb functions with bit 0 of the symbol value.**
It uses the `N_ARM_THUMB_DEF` (`0x0008`) flag in `n_desc`. Disassemble a Thumb
function as ARM and you get plausible-looking garbage.

---

## What is still open

Named here so nobody has to rediscover that they are open:

- **The engine's own tick rate.** Every duration is in game frames, which is
  correct and portable, but what a game frame *is* in wall-clock terms has not
  been recovered. The build has F10/F11 bound to a speed multiplier because of
  this.
- **`AddNewGameEvents` (`0x000732a8`, 6.5 KB)** — the consumer of the event
  queue. It holds the per-character voice table for `MKEvent_Add` subtype 3,
  the real blood particle motion, and the real screen shake amplitude. Until it
  is read, those three are *chosen*.
- **`DrawHUD` (`0x000282dc`, 11.5 KB)** — the HUD layout. The sprites and the
  round tokens are measured; where they sit on screen is read off a screenshot.
- **`seq_lookup`** in `playback.c` — the special-move detector. The one here
  works from the game's own notation tables, but the matcher itself is ours.
