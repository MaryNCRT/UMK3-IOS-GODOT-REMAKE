## A stage's effects: the mist, the torches, the blades in the Pit.
##
## The C project's `runtime/fight_render.c` calls this the mist, because
## Graveyard is where it was worked out, but the machinery is general: a stage's
## `.events` names an effect and gives the transform for each instance, and the
## effect itself is an ordinary file group -- `GYMIST1.meshset` plus
## `GYMIST1.scene` -- drawn the same way the stage is.
##
## ## Three things, and each one was found by it looking wrong
##
## **The instances come from `.events`, not from the scene's markers.** Both
## agree on the positions, but `.events` also carries a 3x3 with a different Y
## scale per instance and two of them turned 180 degrees about Z. Placing them
## by translation alone -- which the C port did first -- stacks seven identical
## bands on top of each other and reads as a flat grey wash.
##
## **The effect has its own `.scene`, and it animates.** GYMIST1's runs 2,001
## frames. That is what makes the fog drift; a static placement is a sheet
## hanging in the air. Here the transforms are updated per frame and the meshes
## are not rebuilt, so the drift costs almost nothing.
##
## **Blending is chosen by the MESH NAME, not by the fact that it is an effect.**
## GYMIST1's mesh is `ALPHA_mist` and PIT_BLADES' is `ALPHA_blade`, so both take
## the blend-with-depth-writes-off path. TORCHFIRE2's is `Plane007` -- no prefix
## -- and the engine draws it OPAQUE; its texture PARTICLE1 is opaque to match.
## Forcing blending on everything, which the C port also did first, quietly
## stops the torches writing depth.
##
## The blend is ADDITIVE and therefore unsorted: a+b+c is the same pixel in any
## order, which is why the original draws its transparent list in insertion
## order with no depth sort anywhere.
##
## ## No game data ships here
extends Node3D

const _Events := preload("res://umk3/umk3_events.gd")
const _MeshSet := preload("res://umk3/umk3_meshset.gd")
const _Scene := preload("res://umk3/umk3_scene.gd")

## How fast an effect's own scene advances. A CHOSEN tempo: the engine's rate
## comes from `next_anirate`, which is not decompiled. The C port picked 30 and
## this matches it so the two builds drift at the same speed.
const EFFECT_HZ := 30.0

## Below this, a node goes on the engine's deferred list and is drawn ADDITIVE
## with depth writes off. Established in the C project by bisection against the
## recompiled original -- 0.9700 behaves as opaque and 0.9699 does not -- and
## not read from a literal.
const OPAQUE_ALPHA := 0.97

var events := _Events.new()
var loaded := 0
var error := ""

## One entry per placed instance: which effect, which of its scene nodes, and
## the `.events` transform it hangs under.
var _parts: Array = []
var _groups := {}
var _time := 0.0


## Build every effect the stage declares. Returns how many instances were placed.
func build(res_dir: String, stage_stem: String, textures) -> int:
	for c in get_children():
		c.queue_free()
	_parts.clear()
	_groups.clear()
	loaded = 0

	if not events.load_file(res_dir.path_join(stage_stem + ".events")):
		error = events.error
		return 0
	if events.tracks.is_empty():
		return 0

	for tr in events.tracks:
		if tr.name == "":
			continue
		# The track name is the effect's file group, upper-cased.
		var group: String = tr.name.to_upper()
		if not _groups.has(group):
			var ms := _MeshSet.new()
			if not ms.load_file(res_dir.path_join(group + ".meshset")):
				continue
			var sc := _Scene.new()
			var has_scene := sc.load_file(res_dir.path_join(group + ".scene"))
			_groups[group] = {"ms": ms, "sc": sc, "has": has_scene, "mat": {}}
		var g: Dictionary = _groups[group]
		var ms2 = g["ms"]
		var sc2 = g["sc"]

		# One node per instance, carrying the `.events` transform; the effect's
		# own scene moves what hangs under it.
		var holder := Node3D.new()
		holder.transform = tr.to_transform()
		holder.name = group
		add_child(holder)

		var by_name := {}
		for i in ms2.meshes.size():
			by_name[ms2.meshes[i].name] = i

		if g["has"] and sc2.nodes.size() > 0:
			for i in sc2.nodes.size():
				var nd = sc2.nodes[i]
				if not by_name.has(nd.name):
					continue
				var mi := _instance(g, ms2.meshes[by_name[nd.name]], textures)
				if mi == null:
					continue
				holder.add_child(mi)
				_parts.append({"node": mi, "scene": sc2, "index": i,
					"mat": mi.mesh.surface_get_material(0)})
				_set_path(mi.mesh.surface_get_material(0), nd)
				loaded += 1
		else:
			for m in ms2.meshes:
				var mi := _instance(g, m, textures)
				if mi == null:
					continue
				holder.add_child(mi)
				loaded += 1

	if loaded > 0:
		_apply(0)
	return loaded


func _instance(g: Dictionary, m, textures) -> MeshInstance3D:
	var arrays := []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = m.positions
	arrays[ArrayMesh.ARRAY_TEX_UV] = m.uvs
	if m.indices.size() > 0:
		arrays[ArrayMesh.ARRAY_INDEX] = m.indices
	elif m.positions.size() % 3 != 0:
		return null
	if m.positions.is_empty():
		return null

	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var cache: Dictionary = g["mat"]
	var key: String = m.name + "|" + m.texture
	if not cache.has(key):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # effect quads are two-sided
		var tex = textures.get_texture(m.texture)
		if tex:
			mat.albedo_texture = tex
		# The name decides the path, and so does the frame's own alpha -- see
		# `_apply`, which is where both are settled, because the alpha changes
		# every frame and the name does not.
		if m.name.begins_with("ALPHA_"):
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
			mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		cache[key] = mat
	am.surface_set_material(0, cache[key])

	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.name = m.name if m.name != "" else "fx"
	return mi


## Move every instance to where its effect's own scene has it on this frame,
## and give it that frame's alpha.
##
## **The alpha is not decoration, it is which path the thing is drawn on.**
## `glColor4f(1, 1, 1, key->alpha)` modulates the effect, and a key under 0.97
## goes on the deferred list: ADDITIVE, depth writes off. At or above it, an
## `ALPHA_` mesh blends normally and anything else is opaque.
##
## Forcing additive on every `ALPHA_` mesh -- which is what this did first --
## turns Graveyard's seven mist bands into a blue wall across the whole screen.
func _apply(frame: int) -> void:
	for p in _parts:
		var sc = p["scene"]
		if sc.num_frames <= 0:
			continue
		var f: int = frame % sc.num_frames
		var pl = sc.placement_for(p["index"], f)
		var mi: MeshInstance3D = p["node"]
		if pl == null:
			mi.visible = false
			continue
		mi.visible = true
		mi.transform = pl.to_transform()

		# The colour is a uniform and costs nothing to change. The blend flags
		# are decided once, in `_set_path`, and never touched here.
		var mat: StandardMaterial3D = p["mat"]
		if mat != null:
			mat.albedo_color = Color(1.0, 1.0, 1.0,
				sc.nodes[p["index"]].alpha[f])


## Which of the engine's three paths this node is drawn on, decided ONCE from
## its whole alpha stream.
##
## **The engine decides this per frame and this does not, on purpose.**
## `glColor4f(1,1,1,key->alpha)` with `key->alpha < 0.97` puts a node on the
## deferred list -- additive, depth writes off -- and at or above it an `ALPHA_`
## mesh blends normally and anything else is opaque. Transparency, blend mode
## and depth mode each select a SHADER VARIANT in Godot, so re-deciding every
## frame rebuilds the material every frame: Balcony's 116 instances and
## Rooftop's seven both ran at 1 fps that way, because their alpha crosses the
## threshold and flipped the flags back and forth.
##
## So: if a node is EVER under the threshold it is additive for its whole life.
## The per-frame alpha still modulates it through the albedo colour, which is a
## uniform and free. The difference shows only on a node that crosses 0.97
## mid-animation, and it costs two orders of magnitude in frame rate not to
## take it.
func _set_path(mat: StandardMaterial3D, nd) -> void:
	if mat == null:
		return
	var ever_under := false
	for a in nd.alpha:
		if a < OPAQUE_ALPHA:
			ever_under = true
			break

	if ever_under:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	elif nd.name.begins_with("ALPHA_"):
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY


func _process(dt: float) -> void:
	if _parts.is_empty():
		return
	_time += dt
	_apply(int(_time * EFFECT_HZ))
