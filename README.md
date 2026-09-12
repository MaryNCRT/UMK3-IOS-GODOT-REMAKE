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

## NO GAME DATA IS IN THE REPOSITORY

Nothing from the game is committed. `.gitignore` excludes `assets/`, and the
repository is code only.

**A working copy is a different thing.** `umk3/umk3_bundle.gd` copies the files
this build actually uses -- 187 of them, followed from the stages' own
references rather than copied wholesale -- into `res://assets/game/`, and the
project then runs on its own with no install path between it and the data:

    godot --headless --path . --script umk3/umk3_bundle.gd -- "X:/UMK3.app/res"

Run it again with extra names to bring one more thing over as it is needed;
it only copies what is missing. A build exported after that **carries EA's
data inside it and is a personal build** -- do not pass it on. Delete
`assets/game` and export again for one that asks for your own `res` folder
instead, which is how it worked before.

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

## Exporting for Blender

    godot --headless --path . --script umk3/umk3_export.gd -- --char SCORPION_STANDARD
    godot --headless --path . --script umk3/umk3_export.gd -- --stages

writes `export/characters/*.glb` and `export/stages/*.glb`, scaled so a
fighter is **1.8 m**, with one animation clip per entry of the engine's
own animation table (82 for Scorpion). `export/` is gitignored: it is
the same game data in another format.

**Characters come out rigged.** A `.skin` does not store a bind pose —
it stores each vertex already multiplied by its weight in each bone's
own frame — and neither the skeleton's offsets nor any of the 344
animation frames turn out to be one. So the bind pose is *recovered*:
585 of Scorpion's 1,278 vertices are shared between two or more bones,
and three shared points fix the rigid transform between two bone frames
exactly, with no fitting. The sweep spreads from there across the
skeleton, and a bone that shares nothing is unconstrained in a way that
does not matter — all of its vertices have a single influence.

That claim is checked rather than asserted:

    godot --headless --path . --script umk3/umk3_checkglb.gd -- --frame 216

loads the `.glb` back, drives its skeleton with a real animation frame,
skins it by hand and compares every vertex against `umk3_skin.gd` — the
function the fight has been drawing with all along. **0.5 mm on a 1.8 m
figure.**

### FBX

Godot has no FBX exporter; its FBX support is an importer. So the FBX is
a conversion, and Blender does the writing:

    godot ... umk3/umk3_export.gd -- --stages --blender "C:/.../blender.exe"

which runs `export/glb_to_fbx.py` over everything it just wrote. That
script is written out whether or not Blender is there, so the step can
be run later by hand. Nothing is lost by stopping at `.glb`: Blender
opens it with the armature, the weights and the clips intact.

### Blender files coming back

`project.godot` turns on `filesystem/import/blender/enabled`, so a
`.blend` dropped into the project imports like any other model — Godot
runs Blender in the background and re-runs it whenever the file changes.
The path to Blender is an **editor** setting, not a project one, because
it is per machine:

    Editor > Editor Settings > FileSystem > Import > Blender > Blender Path

`.fbx` import is on too, and needs nothing external.

## Where the path is remembered

The first working `res` folder is saved to `user://umk3.cfg` and reused,
so the editor's Play button and the Godot MCP server work without
arguments. `user://` is outside the project — nothing about your install
lands in the repository.
