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
    Geometry and placement  done
    Textures                done — PVRTC 2bpp and 4bpp, and PNG
    Lighting                the engine's model, standing in (see below)

### Textures

Legacy **PVR v2** containers, PVRTC1 at 2 or 4 bits per pixel. Decoding is
per-pixel and GDScript is slow at it, so each decode is cached as PNG in
`user://umk3_texcache` — Graveyard's first run is about 9 seconds and every
run after it is 3. The key carries the source file's size and modification
time, so pointing at a different `res` folder invalidates it.

221 of the game's textures are PNG rather than PVRTC and cost nothing;
Godot reads them directly.

### Lighting — read this before trusting it

**The original does not light stages this way.** Stages have baked
per-vertex light in `.lighting` files — 341 of them ship — and *that
encoding is not decoded*. The bytes are 62% zeros with all 256 values
present, which looks like delta coding or compression, and saying more
would be guessing.

What is here instead is `LightVert`, the engine's own model, ported
exactly: two directional lights, **no ambient**, a `pow()` falloff on
each, clamped to 1, and the result written as a monochrome grey
multiplier that can never tint. It is applied to vertex normals that
really are in the `.meshset` and that the iOS loader discards.

So: the game's own light rig, on the game's own normals, but not what
the game displays. `umk3_light.gd` says the same thing at the top.

One number in there is not the engine's: `fill`. A verified zero ambient
and one active light leaves pitch-black backs, which makes a viewer
useless. It is labelled as a viewer affordance in both this project and
the C one.

## Where the path is remembered

The first working `res` folder is saved to `user://umk3.cfg` and reused,
so the editor's Play button and the Godot MCP server work without
arguments. `user://` is outside the project — nothing about your install
lands in the repository.
