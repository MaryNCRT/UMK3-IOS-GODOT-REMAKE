# Getting started

[← README](../README.md)

## What you need

- **Godot 4.4 or newer.** Developed against 4.7.2.
- **Your own copy of *Ultimate Mortal Kombat 3* for iOS, version 1.2.59.**
  Nothing here ships game data and nothing here will download any.

Extract the `.ipa` (it is a zip) and find `Payload/UMK3.app/res`. That folder is
what the project needs. `cryptid` is 0 in this build, so no decryption step is
involved.

## Running it

From a build:

```
UMK3.exe -- "D:/games/UMK3.app/res"
```

From source:

```
godot --path . -- "D:/games/UMK3.app/res"
```

Forward slashes work on Windows and are less trouble in a shell. The path is
remembered in `user://umk3.cfg` after the first run, so later runs need no
argument.

If the path is wrong or missing, the game says so on screen rather than
crashing.

## Where your settings go

Outside the project, under Godot's user directory:

| File | Holds |
|---|---|
| `user://umk3.cfg` | where your `res` folder is |
| `user://umk3_input.cfg` | both players' bindings and device choices |
| `user://umk3_video.cfg` | monitor, resolution, window mode, antialiasing, vsync, frame limit |
| `user://umk3_texcache/` | decoded textures, keyed by source size and timestamp |

On Windows that is `%APPDATA%\Godot\app_userdata\UMK3 (Godot)\`.

The texture cache exists because decoding PVRTC in GDScript is slow. Point the
game at a different `res` folder and the cache invalidates itself.

## Playing

Defaults, both on the keyboard:

| | P1 | P2 |
|---|---|---|
| move / jump / duck | W A S D | arrow keys |
| high punch, low punch | U, I | keypad 7, 8 |
| block | O | keypad 9 |
| high kick, low kick | J, K | keypad 4, 5 |
| run | L | keypad 6 |

`ESC` or a pad's **Start** opens the pause menu. Controls and video options are
both in there, and video is also on the front end.

**A player uses one device.** Choose it on the key config page: keyboard, or a
named pad. A pad belongs to one player at a time; the keyboard can be either.
A player on a pad is *not* also moved by the keyboard.

Pad glyphs follow what you plug in — DualSense, DualShock, Xbox, Pro Controller
— identified by vendor and product id rather than by name, because a DualSense
does not reliably say "DualSense". If it still guesses wrong, the Buttons row
lets you say which pictures to draw.

Scorpion's specials, in the game's own notation (`<-` is away from the
opponent):

| | |
|---|---|
| Spear | `<- <- LP` |
| Teleport punch | `down <- HP` |
| Air throw | `up + BL` |

## Debug keys

| Key | Does |
|---|---|
| `[` `]` | previous / next stage |
| `V` | switch between the fight and the free orbit camera |
| `F5` | reset the round |
| `F6` `F7` | stage fog down / up |
| `F8` `F9` | animation rate bias |
| `F10` `F11` | game speed |
| `H` | draw the hitboxes |

## Command-line flags

Everything after `--` is read by the game. Besides the `res` path:

```
--stage N          go straight into an arena
--drive N          hold a fixed input word for player one
--drive2 N         the same for player two
--seq a,b,c        feed one input word per tick
--shot FILE        screenshot the viewport and quit
--wait N           how many frames to run first
--pose N           freeze both fighters on one animation frame
--hitbox 1         start with the boxes drawn
--gap N            starting half-distance between the fighters
--wins N           put N round tokens on the HUD
--menu 1|2|3       open the pause menu, the key config, or the video page
--fog F            stage fog opacity
--stagelight 0     turn the stage lighting off
```

The input word is the engine's ten bits:
`UP 1, DOWN 2, LEFT 4, RIGHT 8, HP 16, LP 32, BL 64, HK 128, LK 256, RUN 512`.
So `--drive2 18` is down+high punch, an uppercut.

These are how nearly everything in this project is verified. A change to the
fight is checked by driving an input and reading the state back:

```
godot --path . -- --stage 0 --gap 30 --drive2 18 --wait 200 --shot out.png
```

## Working on it

- Read [ARCHITECTURE.md](ARCHITECTURE.md) first; it says which file to open.
- Read [METHODOLOGY.md](METHODOLOGY.md) before changing a constant in
  `umk3_fight.gd`. Those numbers have addresses attached for a reason.
- **Do not hand-edit a generated file.** `umk3_strikes.gd` and
  `umk3_scorpion_ani.gd` say GENERATED at the top. If one is wrong, the
  generator is wrong.
- A headless parse check of everything:

  ```
  godot --headless --path . --script umk3/umk3_check.gd -- "D:/games/UMK3.app/res"
  ```
