## Scorpion's spear, drawn the way the engine draws it.
##
## ## There is no spear model, and that is a finding
##
## Nothing under `res/` holds a spear mesh, and searching the meshsets for one
## was never going to work. The binary says why: `RenderExtras` (0x00020fa8)
## loops over two players' worth of `_SpearStartPos` (0x001ab63c) and
## `_SpearEndPos` (0x001ab624) -- three floats each -- and draws the rope as a
## single textured quad between them, choosing the texture with
##
##     SpearTexture[ SpearWhichTexture[player] % 3 ]
##
## and the head from `SpearTexture[3]`. Those five slots are filled from
## **SPEAR1.PNG, SPEAR2.PNG, SPEAR3.PNG and SPEAR4.PNG**, which are the only
## `SPEAR*` strings in the whole binary. Looking at them settles which is
## which: 1 and 2 are 512x64 ropes with a travelling wave, 3 is the same size
## but the rope drawn straight and taut, and 4 is a 64x64 kunai head pointing
## right.
##
## So the spear is a SPRITE, always was, and the three rope frames cycling at
## one per game frame are what makes it ripple on the way out.
##
## ## What this draws
##
## Two quads in the fight's own space: the rope stretched from Scorpion's hand
## to the head, and the head itself at the tip. The head is drawn 22 units
## square because that is exactly the size of `_stk_scorp_spear`'s box -- the
## thing you can see and the thing that can hit you are the same size, which is
## the only way a projectile reads honestly.
##
## The rope's THICKNESS is chosen: the texture is 64 pixels tall against 512
## wide and nothing says what that is in world units. 26 looks like the rope in
## the art at the scale the head is drawn.
extends Node3D

const ROPE_H := 26.0                    ## chosen -- see above
const HEAD := 22.0                      ## measured, _stk_scorp_spear's box

var _rope: MeshInstance3D
var _head: MeshInstance3D
var _rope_tex: Array = []
var _head_tex: Texture2D = null
var ok := false


func setup(textures) -> void:
	_rope = _make()
	_head = _make()
	for n in ["SPEAR1", "SPEAR2", "SPEAR3"]:
		var t = textures.get_texture(n + ".???")
		if t:
			_rope_tex.append(t)
	_head_tex = textures.get_texture("SPEAR4.???")
	ok = _head_tex != null and not _rope_tex.is_empty()
	visible = false


func _make() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mi.material_override = mat
	add_child(mi)
	return mi


## Place the spear. Every argument is in SCENE units and this frame's own
## numbers -- nothing is remembered between calls, so the drawing can never
## drift from the fight.
##
## `which` is the engine's `SpearWhichTexture`, and taking it modulo the number
## of rope frames is what `RenderExtras` does with it.
func place(hand_x: float, hand_y: float, tip_x: float, tip_y: float,
		which: int, units: float) -> void:
	if not ok:
		return
	visible = true
	var hw := HEAD * units
	var rh := ROPE_H * units

	var mat_r := _rope.material_override as StandardMaterial3D
	mat_r.albedo_texture = _rope_tex[posmod(which, _rope_tex.size())]
	# The rope runs from the hand to the back of the head, so the head is not
	# drawn over by the last of the rope.
	var back_x := tip_x - signf(tip_x - hand_x) * hw * 0.5
	_rope.mesh = _quad(hand_x, hand_y - rh * 0.5, back_x, hand_y + rh * 0.5,
		hand_x > back_x)

	var mat_h := _head.material_override as StandardMaterial3D
	mat_h.albedo_texture = _head_tex
	_head.mesh = _quad(tip_x - hw * 0.5, tip_y - hw * 0.5,
		tip_x + hw * 0.5, tip_y + hw * 0.5, tip_x < hand_x)


func clear() -> void:
	visible = false


## One textured rectangle in the XY plane. `flip` mirrors the U axis, which is
## how a sprite drawn for one facing serves the other -- the same trick the
## fighter's own mirror uses.
static func _quad(x0: float, y0: float, x1: float, y1: float,
		flip: bool) -> ArrayMesh:
	if x1 < x0:
		var t := x0
		x0 = x1
		x1 = t
	var u0 := 1.0 if flip else 0.0
	var u1 := 0.0 if flip else 1.0
	var v := PackedVector3Array([
		Vector3(x0, y0, 0), Vector3(x1, y0, 0), Vector3(x1, y1, 0),
		Vector3(x0, y0, 0), Vector3(x1, y1, 0), Vector3(x0, y1, 0)])
	var uv := PackedVector2Array([
		Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0),
		Vector2(u0, 1), Vector2(u1, 0), Vector2(u0, 0)])
	var arrays := []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = v
	arrays[ArrayMesh.ARRAY_TEX_UV] = uv
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am
