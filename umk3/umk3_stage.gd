## Builds a UMK3 stage as a Godot node tree, from the user's own `res` folder.
##
##     var stage := UMK3Stage.new()
##     stage.build(res_dir, "GRAVEYARD_LEVEL_SCENE")
##     add_child(stage)
##
## ## What this is, and what it is not
##
## It is the asset half of the decompilation project, moved to Godot. The
## `.meshset` and `.scene` formats were recovered from the binary and are
## documented in that project; this reads them and hands Godot an ArrayMesh
## per object, placed by the scene graph.
##
## It is NOT the game. The fight engine is 111,000 lines of C transcribed from
## the binary, and it calls OpenGL directly in 366 places because the original
## did. None of that comes across; what comes across is the knowledge of how
## the files are laid out.
##
## ## No game data ships here
##
## `res_dir` is a path the caller supplies, pointing at their own extracted
## `UMK3.app/res`. Nothing is copied into the project.
class_name UMK3Stage
extends Node3D

const _MeshSet := preload("res://umk3/umk3_meshset.gd")
const _Scene := preload("res://umk3/umk3_scene.gd")
const _Textures := preload("res://umk3/umk3_textures.gd")
const _Light := preload("res://umk3/umk3_light.gd")
const _Effects := preload("res://umk3/umk3_effects.gd")
const _Fighter := preload("res://umk3/umk3_fighter.gd")

## Set before `build` to see what was loaded.
@export var verbose := true

var meshset := _MeshSet.new()
var scene_graph := _Scene.new()
var textures = null
var error := ""

## Light the geometry with `LightVert`, the engine's own model.
##
## **On, by the user's decision, and what that means is worth stating.**
##
## The game does NOT light stages this way. It bakes them, and `.lighting` is
## not decoded -- 341 files, 62% zero bytes, all 256 values present, which looks
## like delta coding and saying more would be guessing. So neither setting here
## is "what the game shows": one is the texture at full brightness, the other is
## the engine's own rig applied to normals that really are in the `.meshset` and
## that the iOS loader discards.
##
## Between two approximations the choice is a look, and looks are the user's
## call: they asked for this one after seeing both side by side. It is darker --
## light 0 ships with a power of zero, so most surfaces get light 1 and the
## viewer's `fill` -- and it gives the stage the depth a night graveyard has
## instead of a flat bright wall.
##
## `--stagelight 0` turns it off; the comparison is two commands away.
@export var use_lighting := true

## How far the stage reaches, in its own units. Worth having: Graveyard's moon
## sits about 27,500 units out, and a camera far plane sized to a fighter
## simply does not contain it -- the C port hit exactly that and drew no moon.
var reach := 0.0


func build(res_dir: String, stem: String, frame: int = 0) -> bool:
	error = ""
	for c in get_children():
		c.queue_free()
	# **The stage is in ENGINE units and the world is in metres.** A stage
	# object and a fighter measured the same before this; scaling the stage node
	# keeps that true and puts both in the unit every other tool uses.
	scale = Vector3.ONE * _Fighter.METRES_PER_UNIT

	if textures == null:
		textures = _Textures.new(res_dir)

	var ms_path := res_dir.path_join(stem + ".meshset")
	var sc_path := res_dir.path_join(stem + ".scene")

	if not meshset.load_file(ms_path):
		error = meshset.error
		return false

	var have_scene := scene_graph.load_file(sc_path)
	if not have_scene and verbose:
		# Not fatal. Some stems have no .scene and are a single object at the
		# origin; the two known stub exports also land here.
		print("[umk3] no usable .scene for %s (%s) -- placing at origin"
			% [stem, scene_graph.error])

	# Index the meshes by name so the scene graph's object names can find them.
	# The original calls LIME_FindMeshByName once per object, always with that
	# object's own name.
	var by_name := {}
	for i in meshset.meshes.size():
		by_name[meshset.meshes[i].name] = i

	var placed := 0
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)

	if have_scene and scene_graph.nodes.size() > 0:
		for i in scene_graph.nodes.size():
			var nd := scene_graph.nodes[i]
			if not by_name.has(nd.name):
				continue
			var p := scene_graph.placement_for(i, frame)
			if p == null:
				continue            # hidden on this frame
			var mi := _make_instance(meshset.meshes[by_name[nd.name]])
			if mi == null:
				continue
			mi.transform = p.to_transform()
			add_child(mi)
			placed += 1
			var aabb := mi.get_aabb()
			lo = lo.min(mi.transform * aabb.position)
			hi = hi.max(mi.transform * aabb.end)
	else:
		for m in meshset.meshes:
			var mi := _make_instance(m)
			if mi == null:
				continue
			add_child(mi)
			placed += 1
			var aabb := mi.get_aabb()
			lo = lo.min(aabb.position)
			hi = hi.max(aabb.end)

	if placed == 0:
		error = "%s: nothing placed" % stem
		return false

	# `reach` is used for the camera's far plane, which is set in world space,
	# so it is reported in METRES like everything else.
	reach = maxf(hi.length(), lo.length()) * _Fighter.METRES_PER_UNIT

	# The stage's effects: the mist in Graveyard, the torches on the Balcony,
	# the blades in the Pit. Placed from `.events`, which is the file that
	# carries a transform per instance and not just a position.
	var fx = _Effects.new()
	add_child(fx)
	var n := fx.build(res_dir, stem, textures)
	if n == 0:
		fx.queue_free()
	elif verbose:
		print("[umk3] %s: %d effect instances" % [stem, n])

	if verbose:
		print("[umk3] %s: variant %s, %d meshes, %d tris, %d placed, reach %.0f"
			% [stem, meshset.variant, meshset.meshes.size(),
			   meshset.total_triangles(), placed, reach])
		print("[umk3] " + textures.report())
	return true


func _make_instance(m) -> MeshInstance3D:
	if m.positions.size() == 0:
		return null

	var arrays := []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = m.positions
	arrays[ArrayMesh.ARRAY_TEX_UV] = m.uvs

	# The engine's lighting is a MONOCHROME grey written as R = G = B, applied
	# as a multiplier over the texture. Handing it to Godot as vertex colour
	# and telling the material to use it reproduces that exactly.
	if use_lighting and m.normals.size() == m.positions.size() \
			and m.normals.size() > 0:
		arrays[ArrayMesh.ARRAY_COLOR] = _Light.colours(m.normals)

	if m.indices.size() > 0:
		arrays[ArrayMesh.ARRAY_INDEX] = m.indices
	elif m.positions.size() % 3 != 0:
		return null                 # variant C with a broken triangle list

	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	# **Unshaded, and that is not laziness.** The original computes lighting
	# per vertex on the CPU and hands it to GL as vertex colour; letting Godot
	# light these as well would double it and look nothing like the game.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true

	var tex: ImageTexture = textures.get_texture(m.texture)
	if tex:
		mat.albedo_texture = tex
		# The atlases wrap, and several stages rely on it -- the cobbles tile.
		mat.texture_repeat = true
		# 320 of the 1,400 textures carry alpha. Alpha-scissor rather than
		# blending: the engine draws these opaque with an alpha TEST, and
		# blending them would sort wrong and haloes the edges.
		if tex.get_image() and tex.get_image().detect_alpha() != Image.ALPHA_NONE:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.alpha_scissor_threshold = 0.5

	am.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.name = m.name if m.name != "" else "mesh"
	mi.set_meta("umk3_texture", m.texture)
	return mi
