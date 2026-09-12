# Ultimate Mortal Kombat 3 — Godot Remake

**A playable remake of the 2011 iOS release of *Ultimate Mortal Kombat 3*, rebuilt in Godot 4 — where every number in the fight comes out of the original binary rather than out of somebody's judgement.**

[Getting started](docs/GETTING-STARTED.md) · [Methodology](docs/METHODOLOGY.md) · [Architecture](docs/ARCHITECTURE.md) · [Fight system](docs/FIGHT-SYSTEM.md) · [Animation](docs/ANIMATION.md) · [Progress](docs/PROGRESS.md) · [AI disclosure](AI-DISCLOSURE.md) · [Español](README.es.md)

**This is the second half of a two-repository project.** The first is
[**Ultimate-Mortal-Kombat-3-iOS-Recomp**](https://github.com/MaryNCRT/Ultimate-Mortal-Kombat-3-iOS-Recomp),
which takes the iOS binary apart. This one puts a game back together from what
that one finds. [How they fit together](#the-two-repositories).

---

## No copyrighted assets are distributed here

**This repository ships no game files.** No textures, no models, no audio, no
frame data — nothing you could extract from here and use. It runs against **a
copy of the game you supply yourself**.

What lives here is code: GDScript that reads the game's own file formats, and a
fight engine whose constants were recovered by reading the retail ARM binary.
Numbers recovered from a binary — a table of hitboxes, a list of animation frame
indices — are facts about how the software behaves, and they are written down
here the way a format specification is written down. The game's files themselves
stay on your disk, where `.gitignore` keeps them out of the repository.

You need a legally obtained copy of *Ultimate Mortal Kombat 3* for iOS
(version 1.2.59) for any of this to do anything.

---

## The two repositories

They are separate projects with separate goals, and each is useful without the
other. They share one thing: the binary, and what has been learned from it.

| | [**Recomp**](https://github.com/MaryNCRT/Ultimate-Mortal-Kombat-3-iOS-Recomp) — step one | **Godot Remake** — step two (this one) |
|---|---|---|
| **Question it answers** | *What does the original do?* | *Can we play it again?* |
| **Output** | Readable C, one function at a time, checked against a static ARM→C recompiler | A running game |
| **Fidelity rule** | The C must match the disassembly | The *behaviour* must match the measurements |
| **Renderer** | The original's own GL calls, transcribed | Godot's, written fresh |
| **Scope** | The whole binary — 4,342 named functions | The fight first, and only Scorpion so far |
| **Finished when** | The C compiles and plays | It plays like the phone game |

**Why two and not one.** The decompilation transcribes the original *including*
the way it talks to the hardware — it calls OpenGL directly in 366 places,
because the 2011 game did. Putting Godot underneath that would mean either
writing a fixed-function GL shim on top of Godot's renderer, or editing the
transcription until it no longer matches the disassembly. The second destroys
the only property that makes a transcription worth having.

So the split runs along the one seam where nothing is lost:

> **The decompilation owns the ANSWERS. The remake owns the ENGINE.**

Recomp reads `strike_check_regs` and works out that a strike box is
`[X + x - w, X + x]` and not `[X + x, X + x + w]`. That fact is not C and it is
not GL — it is just true. This repository takes facts like that and builds
something you can play with them, on a renderer that runs on current hardware,
in a window that resizes, with a gamepad that works.

When a number here has a hex address beside it in a comment, that address is a
citation into the binary Recomp documents. The two repositories are a reference
and an implementation of the same subject.

---

## What works right now

Scorpion, one stage at a time, two players on one machine.

- **Movement** — walk, the run and its 48-unit turbo bar, jump, angled jump, duck, turn
- **Attacks** — 16 strikes with their own hitboxes, damage, chip damage, reactions, sounds, animations and *per-move animation speeds*, including the six attacks that two buttons produce: a high kick becomes a knee inside 74 units, and a roundhouse with the stick held back
- **Block** — standing and ducking, polled the way the engine polls it, and the rule that a low attack beats a standing block
- **Specials** — the spear with its rope and its drag, the teleport punch with its screen wrap, and the air throw
- **Reactions** — hits, knockdowns, the uppercut's launch and its landing, getting up, the round-losing collapse
- **Presentation** — the game's own HUD sprites and round tokens, blood, screen shake, 44 sounds and the stage music
- **Around the game** — a pause menu, per-player key config with mouse and pad support, video options (monitor, resolution, window mode, antialiasing, vertical sync, frame limit), all of it saved between runs

[The full list, with what is measured and what is still chosen](docs/PROGRESS.md).

## What does not

One character of twenty-six. No AI opponent, no match flow, no fatalities, no
front end beyond a stage picker, no online play. Seven of the eighteen arenas
are not wired up yet.

---

## Running it

```
UMK3.exe -- "D:/games/UMK3.app/res"
```

The path points at the `res` folder of your own extracted copy. It is remembered
after the first run. [Longer version](docs/GETTING-STARTED.md).

---

## How the fidelity works

Every constant in the fight is one of three things, and the code says which:

1. **Measured** — read out of the binary, with the address in the comment.
   `const UPCUT_VY := -int(18.0 * ONE)   ## measured, 0xffee0000`
2. **Chosen** — no measurement exists yet, and the comment says so plainly
   rather than leaving you to guess which is which.
3. **Generated** — a table emitted from the binary's own data, like the 27
   strike records or the 82 animation streams. Those files say GENERATED at the
   top and are not edited by hand.

The rule that produced most of the work here: **read the whole function, follow
the chain to the leaf, and measure — never infer from plausibility.** Several of
the things that looked obviously right turned out to be wrong, and the
[methodology page](docs/METHODOLOGY.md) is partly a list of them, because the
mistakes are more instructive than the successes.

---

## Prior work and acknowledgements

- **[Ultimate-Mortal-Kombat-3-iOS-Recomp](https://github.com/MaryNCRT/Ultimate-Mortal-Kombat-3-iOS-Recomp)** — the other half of this project.
- **[ermaccer](https://github.com/ermaccer)** — [UMK3IOS.MeshSetTool](https://github.com/ermaccer/UMK3IOS.MeshSetTool), the first public tool for this game's mesh format and the reference the parser here was checked against.
- **[touchHLE](https://github.com/touchHLE/touchHLE)** — an emulator for iPhone OS applications, used as a behavioural reference.
- **[Godot](https://godotengine.org/)**, **[Capstone](https://www.capstone-engine.org/)**, **[Ghidra](https://ghidra-sre.org/)**.
- The controller glyphs are input-prompt packs kept locally and not redistributed here.

---

## Legal

*Ultimate Mortal Kombat 3* and all related assets are the property of their
respective rights holders. This project is not affiliated with, endorsed by, or
connected to Electronic Arts, Warner Bros. Interactive Entertainment,
NetherRealm Studios, or Midway Games.

The work here is reverse engineering carried out for **interoperability and
preservation**: making software that no longer runs on any current platform run
again, on hardware its owners already have. No game code or data is
redistributed. Everything operates on a copy the user already owns.

This project's own code is released under the [MIT License](LICENSE).
