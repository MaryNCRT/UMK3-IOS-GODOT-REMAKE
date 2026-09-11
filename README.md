# UMK3 — Godot

The asset half of the [UMK3 decompilation](../../umk3repo), in Godot.

## What this is

`.meshset` and `.scene` readers written in GDScript, ported from the C
loaders in that project — which were themselves derived from the
disassembly of `LIME_LoadMeshSet` (armv7 `0x0005ea34`) and
`LIME_LoadScene` (`0x0005f0ac`), and validated against 604 of the 605
shipped files.

With them, Godot can open the game's own stage files directly.

## What this is NOT

It is not the game ported to Godot, and it is not a step toward that.

The fight engine is 111,000 lines of C transcribed from the binary, and
**it calls OpenGL directly in 366 places** — because the original did.
Putting Godot underneath that would mean either writing a GL 1.1
fixed-function shim on top of Godot's renderer, or editing the
transcription so it no longer matches the disassembly. The second
destroys the only property that makes the transcription worth anything.

So what crosses over is the part with no fidelity constraint: **the
knowledge of how the files are laid out.**

## NO GAME DATA IS INCLUDED

Nothing from the game ships here. Every path is supplied at run time and
points at your own extracted `UMK3.app/res`.

## Running

Set `res_dir` on the StageViewer node, or pass it on the command line:

    godot --path . -- "X:\path\to\UMK3.app\res"

    [ and ]   previous / next stage
    drag      orbit
    wheel     zoom
    SPACE     step the scene-graph frame
    ESC       quit

Headless check, which parses every stage and reports:

    godot --headless --path . --script umk3/umk3_check.gd -- "X:\...\res"

## Status

    11 of 11 stages parse, 0 failures.
    Geometry and placement: done.
    Textures: not yet — they are PVRTC in a container this does not read.
    Lighting: not yet — the .lighting files carry per-vertex colour.

Materials are deliberately **unshaded**. The original computes lighting
per vertex on the CPU and calls `glShadeModel(GL_FLAT)` so it is not
interpolated; letting Godot light these would look better than the game
and be wrong.
