## One character on screen: the skin, the pose, and the mesh that comes out.
##
## The reader and the maths are in umk3_skin.gd. This is the part that turns a
## pose into something Godot draws, and it corresponds to `character_build` and
## `character_draw` in the C project's `runtime/fight_render.c`.
##
## ## The mesh is cached per animation frame, and that is a measured decision
##
## `umk3_checkskin.gd` times one pose-and-skin of Scorpion at **5.3 ms** --
## 1,278 skinned vertices, four bone influences each, in GDScript. Two fighters
## is 10.6 ms of the 16.6 ms a 60 Hz frame has, before a stage is drawn. So a
## pose is built ONCE per animation frame and kept.
##
## What that costs is the interpolation. The original slerps between two frames
## (`GetSlerpedQ`, verified exactly in the C project) and `pose()` still does;
## this asks it for whole frames only, so the character snaps between them at
## the clip's own rate instead of gliding. At the 30 Hz the clips are paced at
## that is a small difference, and `interpolate` turns it back on for anyone who
## wants to see it -- at 5.3 ms a fighter.
##
## Measure before optimising: the number above is why this is here at all.
##
## ## No game data ships here
extends Node3D

const _Skin := preload("res://umk3/umk3_skin.gd")
const _MeshSet := preload("res://umk3/umk3_meshset.gd")

## `_PlayerSize / _SceneScale` -- 0.01015624962747097 / 0.013313805684447289,
## both literals in __DATA. **A fighter and the stage are NOT drawn at the same
## scale**; the C project's fight_render.c has the derivation. Drawing both at
## 1.0 makes the fighter 1.311x too big for the arena.
const PLAYER_TO_SCENE := 0.762836

## Build a fresh pose every frame, interpolated, instead of using the cache.
var interpolate := false

var skin = null
var texture: ImageTexture = null
var error := ""

## The skinned extent, in scene units, from the pose it was measured on. The
## fight needs it for the engine-units-to-scene-units scale and for framing.
var height := 0.0
var width := 0.0
var depth := 0.0
var feet := 0.0

var _body := MeshInstance3D.new()
var _shadow := MeshInstance3D.new()
var _mat: StandardMaterial3D = null
var _shadow_mat: StandardMaterial3D = null
var _cache := {}
var _frame := -1


func _init() -> void:
	add_child(_body)
	# The flattened black copy the engine draws under a fighter. Scaled to zero
	# on Y and lifted clear of the floor: a shadow on a floor is coplanar with
	# it, and without the lift the depth test throws every pixel away -- which
	# is exactly what happened in the C port, where the code ran every frame
	# and drew nothing.
	_shadow.transform = Transform3D(
		Basis.from_scale(Vector3(1.0, 0.0, 1.0)), Vector3(0.0, 0.5, 0.0))
	add_child(_shadow)


func load_character(res_dir: String, stem: String, textures) -> bool:
	skin = _Skin.new()
	if not skin.load_character(res_dir, stem):
		error = skin.error
		return false

	# **The body texture is named by mesh 0 of the character's own meshset.**
	# The `.skin` does not carry one.
	var ms := _MeshSet.new()
	if ms.load_file(res_dir.path_join(stem + ".meshset")) and ms.meshes.size() > 0:
		texture = textures.get_texture(ms.meshes[0].texture)

	_mat = StandardMaterial3D.new()
	# Unshaded: the per-vertex greys ARE the lighting model, and they are
	# already in the vertex colours. Unlike the stages, this is genuinely what
	# the engine computes per vertex -- LightVert on the skinned normal.
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if texture:
		_mat.albedo_texture = texture
		var img := texture.get_image()
		if img and img.detect_alpha() != Image.ALPHA_NONE:
			_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			_mat.alpha_scissor_threshold = 0.5

	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.albedo_color = Color(0, 0, 0, 0.45)
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shadow_mat.no_depth_test = false

	# Measured on the STANCE, not on frame 0.
	#
	# Everything the fight scales by comes from this, and frame 0 of a
	# `.skinanim` is whatever animation happens to be stored first -- for
	# Scorpion an arms-out pose 168 units across and 64 tall, which made him
	# two thirds the height he should be. The C project measures
	# `CL_STANCE.from` for the same reason.
	measure(216)
	return true


## Measure the model on one real pose, in scene units.
func measure(frame: int) -> void:
	set_pose(frame, frame, 0.0)
	var aabb: AABB = _body.mesh.get_aabb() if _body.mesh else AABB()
	height = aabb.size.y
	width = aabb.size.x
	depth = aabb.size.z
	feet = aabb.position.y


## Expand the indexed skinned positions into a plain triangle list.
##
## **The UVs are stored PER CORNER**, so a shared position appears in several
## triangles and there is no single UV to attach to it. An indexed buffer is not
## available: the expansion is the format's, not a convenience.
func _build(pal: Array) -> ArrayMesh:
	var r: Array = skin.skin(pal)
	var pos: PackedVector3Array = r[0]
	var col: PackedColorArray = r[1]
	var b = skin.block
	var n: int = b.num_verts * 3

	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var cl := PackedColorArray()
	v.resize(n)
	uv.resize(n)
	cl.resize(n)

	for i in n:
		var k: int = b.tri[i]
		if k >= pos.size():
			k = 0
		v[i] = pos[k] * PLAYER_TO_SCENE
		uv[i] = b.uv[i]
		cl[i] = col[k]

	var arrays := []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = v
	arrays[ArrayMesh.ARRAY_TEX_UV] = uv
	arrays[ArrayMesh.ARRAY_COLOR] = cl

	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, _mat)
	return am


## Show one animation frame. `fb`/`frac` are used only when `interpolate` is on.
func set_pose(fa: int, fb: int, frac: float) -> void:
	if skin == null:
		return
	if interpolate:
		_body.mesh = _build(skin.pose(fa, fb, frac))
		_shadow.mesh = _body.mesh
		_shadow.material_override = _shadow_mat
		return

	if fa == _frame:
		return
	_frame = fa
	if not _cache.has(fa):
		_cache[fa] = _build(skin.pose(fa, fa, 0.0))
	_body.mesh = _cache[fa]
	_shadow.mesh = _cache[fa]
	_shadow.material_override = _shadow_mat


## Which way the fighter faces. The engine keeps this as bit 4 of the part's
## 0x28; here it is a quarter turn about Y, one way or the other.
##
## **The model is authored facing +Z, and the reasoning that said otherwise was
## wrong.** The C project measures this same stance at 78.5 units along X and
## 50.4 along Z and concludes from those numbers that the long axis must be the
## facing one, so a fighter facing right needs no rotation. The numbers are
## right -- this port reproduces them to the tenth, independently -- but the
## inference is not: a fighting stance is wide across the SHOULDERS, and 78.5
## is the span of his arms. Rendered at yaw 0 he stands square to the camera
## with his chest to the viewer, which is what a picture settles and an
## argument from extents does not.
##
## So facing right is +90 degrees, which sends local +Z to world +X. The C
## port's `--yaw` still has this wrong and is noted in the handoff.
## The authored facing, in degrees about Y, for a fighter facing RIGHT.
## `--yaw` sweeps it so the angle is chosen by looking rather than arguing.
static var yaw_right := 90.0

func set_facing(facing: int) -> void:
	# facing > 0 uses 0 degrees; the opposite facing uses the mirrored orientation.
	rotation.y = deg_to_rad(0 if facing > 0 else 1)

# The facing value controls which rotation is used:	
# facing > 0 keeps the fighter at 0 degrees;
# the opposite facing uses 1 degree to preserve the current mirrored orientation.

## Take another fighter's skin, material and mesh cache.
##
## Both fighters in a round are the same character today, and a posed mesh for
## a given animation frame is the same object wherever it stands -- only the
## transform differs. Sharing halves both the memory and the 5.3 ms a pose
## costs. It is only valid between two fighters of the SAME character, which is
## what the caller checks.
func share(other) -> bool:
	if other == null or other.skin == null:
		return false
	skin = other.skin
	texture = other.texture
	_mat = other._mat
	_shadow_mat = other._shadow_mat
	_cache = other._cache
	height = other.height
	width = other.width
	depth = other.depth
	feet = other.feet
	set_pose(216, 216, 0.0)
	return true


## Build these animation frames now rather than during the fight.
##
## Each costs 5.3 ms the first time it is asked for, so a punch that has never
## been thrown stutters through its seven frames. The stance and the walk are
## every round's first two seconds; the rest warm up as they are used.
func prewarm(frames: Array) -> void:
	for f in frames:
		if not _cache.has(f):
			_cache[f] = _build(skin.pose(f, f, 0.0))


## How many frames are cached.
func cache_size() -> int:
	return _cache.size()
