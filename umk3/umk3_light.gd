## The engine's lighting model, ported exactly from `LightVert`.
##
## Recovered from the armv6 slice, where the same source compiles to plain
## scalar VFP: `runtime/lime/light.c`, docs/LIGHTING.md.
##
##     l = 0.0                       # NO AMBIENT -- a literal 0.0f
##     d = -dot(N, L0); if d < 0: d = 0
##     l += power0 * pow(d, exp0)
##     d = -dot(N, L1); if d < 0: d = 0
##     l += power1 * pow(d, exp1)
##     if l > 1.0: l = 1.0
##
## ## Three things that are easy to get wrong, and all three are here
##
## **There is no ambient term.** The accumulator starts at a verified literal
## zero, so a surface facing away from both lights is fully black with nothing
## to lift it.
##
## **The dot product is NEGATED.** The stored vectors point from the surface
## toward the light, the opposite of the usual convention. Flipping the sign
## lights the model inside out.
##
## **Each light is raised to a power**, through a real `pow()` -- twice per
## vertex, per frame, on a 2011 iPhone. That is what gives these characters
## their hard, nearly rim-lit falloff. Substituting `max(0, dot)` looks
## visibly wrong.
##
## The result is ONE float written as R = G = B: lighting here is a grey
## multiplier over the texture and can never tint. Every colour comes from the
## diffuse map.
##
## ## What this is standing in for
##
## The original does NOT use this for stages. Stages have baked per-vertex
## light in `.lighting` files -- 341 of them ship -- and **that encoding is not
## decoded**: the bytes are 62% zeros with all 256 values present, which looks
## like delta coding or compression, and saying more would be guessing.
##
## So this is the engine's own model, applied to normals that really are in the
## `.meshset` and that the iOS loader discards. It is honest lighting from the
## game's own light rig. It is not what the game displays.
class_name UMK3Light
extends RefCounted

## The values the binary ships with, from the globals at 0x001bb874. They are
## NOT unit length -- authored in world units, like positions, which is exactly
## why NormaliseLDirs has to exist.
static var _dir0 := Vector3(68.0, 462.0, 247.0).normalized()
static var _dir1 := Vector3(0.0, -300.0, -50.0).normalized()

## **Light 0 ships with a power of zero**, so as initialised it contributes
## nothing and only light 1 does any work. Either it is switched on at run time
## or it is a disabled experiment; the initialiser alone cannot tell them apart,
## so the shipped values are reproduced unchanged.
const POWER0 := 0.0
const EXP0 := 0.8
const POWER1 := 2.0
const EXP1 := 3.5

## One hard light and a verified zero ambient leaves pitch-black backs, which
## makes a viewer useless. This lifts them and is NOT part of the engine --
## the same affordance `runtime/lime/light.c` carries, under the same name.
static var fill := 0.22


static func vert(n: Vector3) -> float:
	var l := 0.0                        # no ambient

	var d := -n.dot(_dir0)
	if d < 0.0:
		d = 0.0
	l += POWER0 * pow(d, EXP0)

	d = -n.dot(_dir1)
	if d < 0.0:
		d = 0.0
	l += POWER1 * pow(d, EXP1)

	l += fill                           # viewer only

	return minf(l, 1.0)                 # ceiling, verified at 0x83c04


## Monochrome, as DrawSkinnedMesh2 writes it: R = G = B, alpha 255.
static func colours(normals: PackedVector3Array) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(normals.size())
	for i in normals.size():
		var g := vert(normals[i])
		out[i] = Color(g, g, g, 1.0)
	return out
