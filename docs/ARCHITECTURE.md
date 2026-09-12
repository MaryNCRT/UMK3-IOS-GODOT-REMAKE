# Architecture — how the code is laid out

[← README](../README.md)

Every script is in `umk3/`, and every one of them opens with a doc comment
explaining what it does and — where it matters — which function in the binary
it came from. **Those comments are the real documentation.** This page is the
map that tells you which file to open.

12,000 lines of GDScript, 41 files, no scene tree to speak of: `main.tscn` has
one node running `umk3_main.gd`, and everything else is built in code. That is
deliberate. The fight is a state machine with fixed-point integer physics, and
a state machine reads better as code than as a node graph.

---

## The shape of it

```
main.tscn
└── umk3_main.gd            the shell: front end, stage, pause, video
    ├── umk3_menu.gd        title / main / stage picker
    ├── umk3_stage.gd       builds one arena as a node tree
    │   ├── umk3_scene.gd       .scene   — where each object goes
    │   ├── umk3_meshset.gd     .meshset — the geometry
    │   ├── umk3_events.gd      .events  — which effects the stage declares
    │   ├── umk3_effects.gd     mist, torches, the Pit's blades
    │   ├── umk3_light.gd       the engine's own vertex lighting
    │   └── umk3_textures.gd    PVR/PNG resolution and a disk cache
    │       └── umk3_pvr.gd     PVRTC decoder
    ├── umk3_fight.gd       THE FIGHT — physics, states, hits, camera
    │   ├── umk3_fighter.gd     one character on screen
    │   │   └── umk3_skin.gd    .bones / .skin / .skinanim and the pose
    │   ├── umk3_strikes.gd     GENERATED: the 27 strike records
    │   ├── umk3_scorpion_ani.gd GENERATED: the 82 animation streams
    │   ├── umk3_moves.gd       special-move notation and the detector
    │   ├── umk3_spear.gd       the spear projectile and its rope
    │   ├── umk3_blood.gd       blood particles
    │   ├── umk3_audio.gd       the sound groups
    │   └── umk3_hud.gd         health bars, run meter, round tokens
    ├── umk3_input.gd       the ten bits, the bindings, the devices
    │   └── umk3_glyphs.gd      button pictures
    ├── umk3_inputhud.gd    the side panel
    ├── umk3_pause.gd       pause menu and key config
    ├── umk3_options.gd     video options page
    └── umk3_video.gd       the video settings themselves
```

---

## The fight, in one page

`umk3_fight.gd` is the only large file, and it is large because it is the game.
Read it in this order:

**1. The constants at the top.** Roughly 600 lines of them, each labelled
measured, chosen or generated. This is where the project's fidelity actually
lives. Walls, floor, camera width, jump velocity, gravity, walk speeds, strike
animations and rates, block timings, the turbo bar, the uppercut's launch.

**2. `class Fight`.** One fighter's state: position and velocity as 16.16
fixed point — `x`, `y`, `vx`, `vy`, `g` — because the original's are, and
floating point would drift away from the measured numbers. Plus the state
enum, the animation clock, and the special-move buffer.

**3. `tick()`.** One game frame, in the order the engine does it:

```
read both players' input
_swscan        edge-detect the six buttons, for both, once   (swscan)
_think         the state machine, per fighter                (plyrthread)
animation clock
_raise_turbo   the run bar regenerates                       (RaiseTurboBars)
_resolve_hits  attacker against victim, both ways            (strike_check_regs)
_step_spear    the projectile
_repell        push the two apart / reel them in             (repell_func)
gravity, integration, walls, floor                           (gravity_n_bounds)
```

**4. `_think()`.** The state machine. A `match` over `St`, one branch per
state, each transcribed from the corresponding `t_*` proc. Read the branch,
then read the proc it names in the comment.

**5. `_resolve_hits()`.** Box against box, then `_is_he_blocking`, then damage
or chip damage, then the reaction. This function and
[FIGHT-SYSTEM.md](FIGHT-SYSTEM.md) explain each other.

### Two things that will confuse you otherwise

**Fixed point.** `ONE` is `1 << 16`. `f.x` is a 16.16 value; `f.xi()` is the
integer part. Velocities are per game frame. A literal like `int(8.0 * ONE)` is
"eight units a frame", and it matches the `0x80000` the binary stores.

**The engine's y grows downward.** `FLOOR_Y` is 247 and a fighter in the air
has a *smaller* y — a launched one goes negative. `_scene_y()` is the only
place that flips it for Godot.

---

## The other clusters

### Assets — reading the game's own files

The format readers are ports of the C loaders in the
[decompilation repository](https://github.com/MaryNCRT/Ultimate-Mortal-Kombat-3-iOS-Recomp),
which were themselves derived from the disassembly of `LIME_LoadMeshSet`
(`0x0005ea34`) and `LIME_LoadScene` (`0x0005f0ac`). The `.meshset` reader was
validated against 604 of the 605 shipped files with an exact final offset.

`umk3_textures.gd` caches decoded PVRTC as PNG under `user://`, keyed by the
source file's size and modification time, because decoding a 512×512 PVRTC
texture in GDScript is slow and a stage wants twenty of them.

### Input — ten bits and nothing else

`umk3_input.gd` owns the contract. The fight receives a ten-bit word:

```
0 UP   1 DOWN   2 LEFT   3 RIGHT   4 HP   5 LP   6 BL   7 HK   8 LK   9 RUN
```

That order is not a convention, it is measured: `swscan` →
`stack_switch_bits` → `_swtab` → `QueueAndJump` → the button table at
`pl->0x60`, and the four tables at `_bt_stance`, `_bt_duck`, `_bt_jump`,
`_bt_angle_jump` hold exactly the moves this port's tables hold.

What produces each bit is the only part that is this project's to choose, and
it is per player, per device, saved in `user://umk3_input.cfg`.

### The shell — menus, pause, video

Ordinary Godot UI, and marked as such: none of it is in the original, which
runs at 480×320 on a phone with no options. `umk3_video.gd` carries the
settings, `umk3_options.gd` draws them, and both the front end and the pause
menu show the *same* node so a change in one is already true in the other.

### Tools — the scripts that are not the game

`umk3_export.gd`, `umk3_import.gd`, `umk3_bundle.gd`, `umk3_framey.gd`,
`umk3_bindprobe.gd`, `umk3_checkglb.gd`, `umk3_checkskin.gd`,
`umk3_posebench.gd`, `umk3_fxprobe.gd`, `umk3_dumptex.gd`, `umk3_check.gd`.

These run headless with `--script` and exist to answer one question each —
"how high off its origin is each animation frame?", "does the exported rig
deform like the engine's?". They are how several of the measured numbers were
checked. They are not part of the game and nothing in the game imports them.

---

## Debug flags

`umk3_main.gd` parses these after `--`, and they are how almost everything in
this project gets verified:

| Flag | Does |
|---|---|
| `--stage N` | go straight into an arena |
| `--drive N` / `--drive2 N` | hold a fixed input word for player one / two |
| `--seq a,b,c` | feed one input word per tick |
| `--shot FILE` / `--wait N` | screenshot the viewport after N frames and quit |
| `--pose N` | freeze both fighters on one animation frame |
| `--hitbox 1` | draw the boxes |
| `--gap N` | set the starting distance |
| `--wins N` | put N round tokens on the HUD |
| `--menu 1\|2\|3` | open the pause menu, the key config, or the video page |

`--shot` renders the game's *own* viewport to a PNG. Nothing here screen-scrapes
the desktop.

---

## Conventions

- **Tabs**, as Godot writes them.
- **`##` doc comments** on every file and on anything non-obvious, and they
  explain *why*, with the binary address when there is one.
- **`preload`, not `class_name`**, for anything the headless scripts touch — a
  `class_name` is invisible until the editor has indexed the project, which is
  exactly when a fresh checkout runs.
- **Generated files are not hand-edited.** If one is wrong, the generator is
  wrong.
- **A number with no address gets the word "chosen"** next to it.
