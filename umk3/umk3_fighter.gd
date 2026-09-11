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

## **The world is in METRES.**
##
## `_ochar_ground_offsets` says a fighter is 139 engine units tall and the
## skinned model measures 140.1 of its own, so one engine unit was one model
## unit -- but neither is a metre, and a scene where a man is 140 units tall is
## a scene no other tool agrees with. A fighter is 1.8 m, so one engine unit is
## 1.8 / 139 metres and the model is scaled to match.
##
## Everything that was in engine units is multiplied by this in ONE place per
## system: here for the model, `scale_units` in the fight for positions, and the
## stage node's own scale. Nothing else changes, because every other number in
## the fight is a ratio.
const FIGHTER_METRES := 1.8
const ENGINE_HEIGHT := 139.0
const METRES_PER_UNIT := FIGHTER_METRES / ENGINE_HEIGHT

## Build a fresh pose every frame, INTERPOLATED between the two the clip is
## between, which is what the engine does.
##
## The alternative -- caching whole frames and snapping between them -- was a
## concession to the 5.3 ms a pose costs in GDScript, and it is not what the
## original does. It stays available (`interpolate = false`) because a machine
## that cannot afford the skinning should drop the in-betweens rather than the
## frame rate, but it is not the default and it is not what ships.
var interpolate := true

## Use the imported Skeleton3D scene instead of skinning here.
##
## **Off, and it is off because it does not work yet.** umk3_import.gd builds a
## real Godot skinned mesh out of the same data, and driving it deforms the
## model -- the head sinks into the shoulders -- even in the bind pose the mesh
## was built for, where it ought to be exact by construction. That is a fault in
## the conversion, not in the data, and until it is found the engine's own CPU
## skinning is the correct path and the one the fight uses.
##
## The import is still worth having: it puts the model, its bones and its 97
## named clips in the editor, which is what it was asked for.
var use_imported := false

var skin = null
var texture: ImageTexture = null
var _stem := ""
var error := ""

## The skinned extent, in scene units, from the pose it was measured on. The
## fight needs it for the engine-units-to-scene-units scale and for framing.
var height := 0.0
var width := 0.0
var depth := 0.0
var feet := 0.0

## The imported model, when `res://assets/characters/<NAME>/model.tscn` exists:
## a Skeleton3D with a skinned mesh, so posing costs 48 quaternions a frame on
## the GPU instead of 5.3 ms of GDScript. umk3_import.gd builds it and measures
## what the conversion costs.
var _model: Node3D = null
var _skel: Skeleton3D = null
## A second copy, flattened onto the floor: the engine's own shadow pass.
var _shadow_model: Node3D = null
var _shadow_skel: Skeleton3D = null

var _body := MeshInstance3D.new()
var _shadow := MeshInstance3D.new()
var _mat: StandardMaterial3D = null
var _shadow_mat: StandardMaterial3D = null
var _cache := {}
var _frame := -1

## The pose-independent half of the mesh, built once by `_build_topology`.
var _src := PackedInt32Array()       ## distinct vertex -> skinned position
var _uv := PackedVector2Array()      ## its UV
var _idx := PackedInt32Array()       ## the triangle list, into those
var unique_verts := 0

## A rolling average of what one interpolated pose costs, in microseconds.
## Interpolating means rebuilding the mesh every frame, so this is the number
## that decides whether it can stay on. Shown in the HUD.
var pose_usec := 0.0


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
	_stem = stem
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

	if use_imported:
		_try_imported()

	# Measured on the STANCE, not on frame 0.
	#
	# Everything the fight scales by comes from this, and frame 0 of a
	# `.skinanim` is whatever animation happens to be stored first -- for
	# Scorpion an arms-out pose 168 units across and 64 tall, which made him
	# two thirds the height he should be. The C project measures
	# `CL_STANCE.from` for the same reason.
	measure(216)
	# The model's own units into metres: it measured `height` tall and a fighter
	# is 1.8 m.
	if height > 0.0:
		var s := FIGHTER_METRES / height
		_body.scale = Vector3(s, s, s)
		_shadow.transform = Transform3D(
			Basis.from_scale(Vector3(s, 0.0, s)), Vector3(0.0, 0.01, 0.0))
		measure(216)
	return true


## The scene built by umk3_import.gd, if it has been built.
##
## Optional on purpose: the CPU path is the engine-exact one and still works on
## its own, so a checkout with no imported assets runs -- slower, and snapping
## between whole frames instead of interpolating.
func _try_imported() -> bool:
	var path := "res://assets/characters/%s/model.tscn" % _stem
	if not ResourceLoader.exists(path):
		return false
	var packed: PackedScene = load(path)
	if packed == null:
		return false

	_model = packed.instantiate()
	_skel = _model.get_node_or_null("Skeleton3D")
	if _skel == null:
		_model.queue_free()
		_model = null
		return false
	# The AnimationPlayer is for the editor. The fight drives bones directly,
	# because WHICH frame shows is a decision the fight makes from its own
	# state -- there is no clip playing on a clock.
	var ap := _model.get_node_or_null("AnimationPlayer")
	if ap:
		_model.remove_child(ap)
		ap.queue_free()
	add_child(_model)

	# The shadow is the whole model again with Y scaled to nothing. A skinned
	# mesh lives in its SKELETON's space, so flattening the mesh instance does
	# nothing and flattening the node above the skeleton does what is wanted.
	_shadow_model = packed.instantiate()
	_shadow_skel = _shadow_model.get_node_or_null("Skeleton3D")
	var sap := _shadow_model.get_node_or_null("AnimationPlayer")
	if sap:
		_shadow_model.remove_child(sap)
		sap.queue_free()
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color(0, 0, 0, 0.45)
	black.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	black.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sbody := _shadow_model.get_node_or_null("Skeleton3D/Body")
	if sbody:
		sbody.material_override = black
	_shadow_model.transform = Transform3D(
		Basis.from_scale(Vector3(1.0, 0.0, 1.0)), Vector3(0.0, 0.5, 0.0))
	add_child(_shadow_model)

	_body.visible = false
	_shadow.visible = false
	return true


## Measure the model on one real pose, in scene units.
##
## Always through the CPU skinner, even when the GPU path is in use: a skinned
## mesh's AABB does not follow its pose, so asking Godot would return the bind
## pose's box whatever is on screen.
func measure(frame: int) -> void:
	set_pose(frame, frame, 0.0)
	var sc: float = _body.scale.y
	if _skel != null and skin != null:
		var r: Array = skin.skin(skin.pose(frame, frame, 0.0))
		var pos: PackedVector3Array = r[0]
		if pos.is_empty():
			return
		var lo := pos[0] * PLAYER_TO_SCENE
		var hi := lo
		for p in pos:
			var q: Vector3 = p * PLAYER_TO_SCENE
			lo = Vector3(minf(lo.x, q.x), minf(lo.y, q.y), minf(lo.z, q.z))
			hi = Vector3(maxf(hi.x, q.x), maxf(hi.y, q.y), maxf(hi.z, q.z))
		height = (hi.y - lo.y) * sc
		width = (hi.x - lo.x) * sc
		depth = (hi.z - lo.z) * sc
		feet = lo.y * sc
		return
	var aabb: AABB = _body.mesh.get_aabb() if _body.mesh else AABB()
	height = aabb.size.y * sc
	width = aabb.size.x * sc
	depth = aabb.size.z * sc
	feet = aabb.position.y * sc


## Expand the indexed skinned positions into a plain triangle list.
##
## **The UVs are stored PER CORNER**, so a shared position appears in several
## triangles and there is no single UV to attach to it. An indexed buffer is not
## available: the expansion is the format's, not a convenience.
func _build(pal: Array) -> ArrayMesh:
	if _src.is_empty():
		_build_topology()

	var r: Array = skin.skin(pal)
	var pos: PackedVector3Array = r[0]
	var col: PackedColorArray = r[1]
	var n := _src.size()

	# **Local arrays, not members, and that is worth 60 frames a second.**
	#
	# Packed arrays are copy-on-write. Keeping these as members to avoid
	# reallocating them means something else is still holding a reference when
	# the next frame writes into them, so EVERY element assignment copies the
	# whole array: the same code ran at 1 fps. A local array has one reference
	# and is written in place.
	var v := PackedVector3Array()
	var cl := PackedColorArray()
	v.resize(n)
	cl.resize(n)
	for i in n:
		var k := _src[i]
		v[i] = pos[k] * PLAYER_TO_SCENE
		cl[i] = col[k]

	var arrays := []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = v
	arrays[ArrayMesh.ARRAY_TEX_UV] = _uv
	arrays[ArrayMesh.ARRAY_COLOR] = cl
	arrays[ArrayMesh.ARRAY_INDEX] = _idx

	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, _mat)
	return am


## The part of the mesh that never changes: work it out once.
##
## **The UVs are stored PER CORNER**, so a shared position carries a different
## UV in each triangle it appears in, and the obvious response -- expand to one
## vertex per corner, 7,509 of them -- costs 1.3 ms a frame to rewrite when the
## character is rebuilt every frame for interpolation.
##
## But a corner is only distinct when its POSITION INDEX AND ITS UV differ, and
## most are not: Scorpion's 7,509 corners are far fewer distinct pairs. Those
## are found here, once, along with the index buffer and the UV array -- neither
## of which depends on the pose. What is left per frame is writing a position
## and a colour for each distinct vertex.
func _build_topology() -> void:
	var b = skin.block
	var n: int = b.num_verts * 3
	var seen := {}
	_src = PackedInt32Array()
	_uv = PackedVector2Array()
	_idx = PackedInt32Array()
	_idx.resize(n)

	for i in n:
		var k: int = b.tri[i]
		if k >= b.num_matrices:
			k = 0
		var uv: Vector2 = b.uv[i]
		var key := "%d|%.6f|%.6f" % [k, uv.x, uv.y]
		var at: int = seen.get(key, -1)
		if at < 0:
			at = _src.size()
			seen[key] = at
			_src.append(k)
			_uv.append(uv)
		_idx[i] = at

	unique_verts = _src.size()
	print("[umk3] %s: %d corners -> %d distinct vertices"
		% [_stem, n, unique_verts])


## Show one animation frame. `fb`/`frac` are used only when `interpolate` is on.
func set_pose(fa: int, fb: int, frac: float) -> void:
	if skin == null:
		return
	if _skel != null:
		_pose_bones(_skel, fa, fb, frac)
		if _shadow_skel != null:
			_pose_bones(_shadow_skel, fa, fb, frac)
		return
	if interpolate:
		var t0 := Time.get_ticks_usec()
		_body.mesh = _build(skin.pose(fa, fb, frac))
		_shadow.mesh = _body.mesh
		_shadow.material_override = _shadow_mat
		var dt := float(Time.get_ticks_usec() - t0)
		pose_usec = dt if pose_usec == 0.0 else pose_usec * 0.9 + dt * 0.1
		return

	if fa == _frame:
		return
	_frame = fa
	if not _cache.has(fa):
		_cache[fa] = _build(skin.pose(fa, fa, 0.0))
	_body.mesh = _cache[fa]
	_shadow.mesh = _cache[fa]
	_shadow.material_override = _shadow_mat


# =============================================================================
# SETTLED -- DO NOT CHANGE. The facing is yaw 0 plus a MIRROR.
#
# Decided by the person who can see the screen, against a retail frame, after I
# got it wrong twice in one day. If a future reading of the data seems to argue
# for something else, the data is not the authority here: the retail frame is.
# Change this only if the USER says the fighters look wrong.
# =============================================================================

## The authored facing, in degrees about Y, for a fighter facing RIGHT.
##
## **Zero. These models are sculpted in three-quarter view** -- the same stance
## the arcade's digitised actors were photographed in -- so at 0 a fighter is
## already angled toward his opponent with his front half toward the camera.
##
## I broke this twice in one day and both mistakes are worth keeping. First I
## reasoned from an extent -- Scorpion measures 78.5 along X against 50.4 along
## Z, so the long axis "must" be the facing one -- when 78.5 is the span of his
## ARMS. Then, when the fighters looked wrong, I turned a working 0 into 90 and
## made it worse, because the real fault was never the yaw.
##
## `--yaw` sweeps it, so the next character is checked by looking.
static var yaw_right := 0.0


## Which way the fighter faces. The engine keeps this as bit 4 of the part's
## 0x28.
##
## **The other side is a MIRROR, not a turn.** A 2D fighting game flips its
## sprite; it does not walk the actor around behind himself. Rotating this model
## 180 degrees shows his BACK, which is a view the game never has -- in any
## retail frame both fighters face the camera three-quarters on, the second one
## being the first one flipped.
##
## Godot's `scale.x = -1` is not the way to ask for that: Transform3D keeps its
## basis orthonormalised on read-back, so a negative scale round-trips into
## something else and the flip silently stops happening. Writing the basis
## directly does exactly one thing and keeps doing it.
##
## The reflection reverses triangle winding, and nothing here depends on it: the
## material is CULL_DISABLED and the lighting is already baked into the vertex
## colours, so the greys stay the un-mirrored model's -- which is what the
## original does too, since it mirrors after lighting.
func set_facing(facing: int) -> void:
	var b := Basis.IDENTITY.rotated(Vector3.UP, deg_to_rad(yaw_right))
	if facing < 0:
		b = Basis(-b.x, b.y, b.z)
	transform = Transform3D(b, position)


## Write one interpolated moment into a Skeleton3D.
##
## The blend is the engine's: a LERP with a shortest-arc sign flip, not a slerp
## -- `GetSlerpedQ` has no acos, no sin and no renormalisation, and substituting
## a real slerp changes every in-between pose. Godot's `Quaternion.slerp` is
## therefore NOT what goes here, even though it is right there.
##
## Bone slot N takes animation slot N: the frames are indexed by the depth-first
## VISIT order, which is the order umk3_import.gd added the bones in.
func _pose_bones(sk: Skeleton3D, fa: int, fb: int, frac: float) -> void:
	fa = clampi(fa, 0, skin.num_frames - 1)
	fb = clampi(fb, 0, skin.num_frames - 1)
	var base_a: int = skin.anim_header + fa * skin.frame_size
	var base_b: int = skin.anim_header + fb * skin.frame_size
	var n: int = mini(sk.get_bone_count(), skin.anim_bones)

	# The root's position is interpolated the same way, through LerpVector3.
	var ra := Vector3(skin.anim.decode_float(base_a + 4),
		skin.anim.decode_float(base_a + 8),
		skin.anim.decode_float(base_a + 12))
	var rb := Vector3(skin.anim.decode_float(base_b + 4),
		skin.anim.decode_float(base_b + 8),
		skin.anim.decode_float(base_b + 12))
	sk.set_bone_pose_position(0, ra.lerp(rb, frac) * PLAYER_TO_SCENE)

	for slot in n:
		var oa: int = base_a + 16 + slot * 20
		var ob: int = base_b + 16 + slot * 20
		var qa := Quaternion(skin.anim.decode_float(oa),
			skin.anim.decode_float(oa + 4),
			skin.anim.decode_float(oa + 8),
			skin.anim.decode_float(oa + 12))
		var qb := Quaternion(skin.anim.decode_float(ob),
			skin.anim.decode_float(ob + 4),
			skin.anim.decode_float(ob + 8),
			skin.anim.decode_float(ob + 12))
		var dot := qa.x * qb.x + qa.y * qb.y + qa.z * qb.z + qa.w * qb.w
		var s := -1.0 if dot < 0.0 else 1.0
		var q := Quaternion(
			qa.x * (1.0 - frac) + qb.x * s * frac,
			qa.y * (1.0 - frac) + qb.y * s * frac,
			qa.z * (1.0 - frac) + qb.z * s * frac,
			qa.w * (1.0 - frac) + qb.w * s * frac)
		if q.length_squared() <= 0.0:
			q = Quaternion.IDENTITY
		sk.set_bone_pose_rotation(slot, q.normalized())


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
	_stem = other._stem
	# Its OWN model: two fighters share the data, but each needs a skeleton of
	# its own to stand in a different pose.
	if use_imported:
		_try_imported()
	height = other.height
	width = other.width
	depth = other.depth
	feet = other.feet
	# **And the scale, which is not part of the mesh.** Sharing copied the
	# measurements and left the node at 1.0, so the second fighter stood 140
	# metres tall and filled the screen with a dark wall nobody recognised as a
	# fighter.
	_body.scale = other._body.scale
	_shadow.transform = other._shadow.transform
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
