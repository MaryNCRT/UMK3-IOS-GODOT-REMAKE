## Characters: `.bones`, `.skin`, `.skinanim`, and the pose that joins them.
##
## Ported from `runtime/lime/skin.c`, derived from `LIME_LoadBones`,
## `LIME_LoadSkin1`, `UnpackAnimFrame` and `DrawSkinnedMesh2`. The spec is
## docs/SKIN-FORMAT.md.
##
## The maths this performs is verified in the C project against the recompiled
## original over 18,780 cases -- MatrixMul2, GetMFromQuat2, GetSlerpedQ and
## Xform2 all exactly. What is NOT verified there, and is not here either, is
## the skeleton walk: `CreateMatrixPaletteRecurse2` is stateful across four
## globals rather than a function of its arguments, so no differential test
## drives it. It produces a character that stands up and moves, which is
## evidence and not proof.
##
## ## Three things that are easy to get wrong
##
## **One animation frame is consumed per bone VISITED, not per bone index.**
## The frames are indexed by depth-first visit order. That is what makes the
## original's four globals globals, and reading them by bone index bends the
## skeleton in a way that looks like bad data.
##
## **The root is the bone nobody claims as a child.** All nine slots in a bone
## record are children; reading slot 0 as a parent link double-counts at once.
##
## **`indexes` is FOUR PACKED BYTES, unsigned.** 0xFF marks an unused
## influence. Read as a signed int32 they look like negative numbers.
##
## ## No game data ships here
class_name UMK3Skin
extends RefCounted

const _Light := preload("res://umk3/umk3_light.gd")

const MAX_BONES := 128

class Bone extends RefCounted:
	var offset := Vector3.ZERO       ## from the parent
	var child := PackedInt32Array()  ## nine slots, -1 unused
	var num_children := 0

class Block extends RefCounted:
	var num_matrices := 0            ## skinned VERTICES, despite the name
	var num_verts := 0               ## TRIANGLES, despite the name
	var indexes := PackedInt32Array()
	var weights := PackedFloat32Array()
	var a := PackedFloat32Array()    ## N*12: four vec3, position, pre-weighted
	var b := PackedFloat32Array()    ## N*12: four vec3, normal, pre-weighted
	var tri := PackedInt32Array()
	var uv := PackedVector2Array()

var bones: Array[Bone] = []
var root := 0

var block: Block = null

var anim := PackedByteArray()
var num_frames := 0
var frame_size := 0
var anim_bones := 0
var anim_header := 12

var error := ""


static func _f(b: PackedByteArray, at: int) -> float:
	return b.decode_float(at)


# ------------------------------------------------------------------- .bones
func load_bones(path: String) -> bool:
	bones.clear()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		error = "no " + path
		return false
	var d := f.get_buffer(f.get_length())
	f.close()
	if d.size() < 4:
		error = path + " is too short"
		return false

	var n := d.decode_s32(0)
	if n <= 0 or n > MAX_BONES:
		error = "%s: %d is not a bone count" % [path, n]
		return false

	# **25 bytes per bone, except ROBO1 and ROBO2, which use 24.**
	#
	# The C loader declines those two on the grounds that guessing which field
	# lost a byte is guessing. It turns out not to be a guess: read with EIGHT
	# child slots instead of nine, both files land exactly on EOF, every child
	# index is in range, `num_children` never exceeds 8, exactly one bone is
	# unclaimed and none is claimed twice -- and ROBO1's first two bones come
	# out at (0.04, 106.07, -3.71) and the origin, the same shape as every
	# other skeleton here. Five structural checks agreeing is evidence; the
	# byte count on its own would not have been.
	var stride := 25
	if 4 + n * stride != d.size():
		stride = 24
		if 4 + n * stride != d.size():
			error = "%s: %d bones fits neither 25 nor 24 bytes in %d" \
				% [path, n, d.size()]
			return false
	var slots := stride - 16

	for i in n:
		var rec := 4 + i * stride
		var bo := Bone.new()
		# **`num_children` is not the number of filled slots.** Every skeleton
		# here has a bone whose count reads 2 with one slot filled. The slots
		# are what is walked and this is only recorded.
		bo.num_children = d.decode_s32(rec)
		bo.offset = Vector3(_f(d, rec + 4), _f(d, rec + 8), _f(d, rec + 12))
		bo.child.resize(slots)
		for j in slots:
			bo.child[j] = d.decode_s8(rec + 16 + j)
		bones.append(bo)

	# The root is the bone nobody claims.
	var claimed := PackedByteArray()
	claimed.resize(n)
	for i in n:
		for j in slots:
			var c := bones[i].child[j]
			if c >= 0 and c < n:
				claimed[c] = 1
	root = 0
	for i in n:
		if claimed[i] == 0:
			root = i
			break
	return true


# -------------------------------------------------------------------- .skin
func _read_block(d: PackedByteArray, at: int, out: Block) -> int:
	if at + 8 > d.size():
		return -1
	var N := d.decode_s32(at)
	var M := d.decode_s32(at + 4)
	if N <= 0 or M <= 0:
		return -1
	var need := 8 + N * 108 + M * 30
	if at + need > d.size():
		return -1

	out.num_matrices = N
	out.num_verts = M
	out.indexes.resize(N)
	out.weights.resize(N * 4)
	out.a.resize(N * 12)
	out.b.resize(N * 12)
	out.tri.resize(M * 3)
	out.uv.resize(M * 3)

	var p := at + 8
	for i in N:
		out.indexes[i] = d.decode_u32(p + i * 4)
	p += N * 4

	# uint16 fixed point, 1/65536 -- the literal at 0x00060634
	for i in N * 4:
		out.weights[i] = float(d.decode_u16(p + i * 2)) / 65536.0
	p += N * 8

	# entries are { MATRIX43 a; MATRIX43 b; } -- 96 bytes, A then B
	for i in N:
		var e := p + i * 96
		for k in 12:
			out.a[i * 12 + k] = _f(d, e + k * 4)
			out.b[i * 12 + k] = _f(d, e + 48 + k * 4)
	p += N * 96

	# vertData: M * 24 -- three UV pairs, one per triangle corner
	for i in M * 3:
		out.uv[i] = Vector2(_f(d, p + i * 8), _f(d, p + i * 8 + 4))
	p += M * 24

	# vertExtra: M * 6 -- three uint16 indices into the skinned positions
	for i in M * 3:
		out.tri[i] = d.decode_u16(p + i * 2)

	return at + need


func load_skin(path: String) -> bool:
	block = null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		error = "no " + path
		return false
	var d := f.get_buffer(f.get_length())
	f.close()
	if d.size() < 4:
		error = path + " is too short"
		return false

	var count := d.decode_s32(0)
	if count == 1 or count == 2:
		# Only the first block is kept: it is the body, and the second is a
		# variant the C port does not draw either.
		var at := 4
		var first := Block.new()
		at = _read_block(d, at, first)
		if at < 0:
			error = path + ": block 0 does not fit"
			return false
		block = first
		for i in count - 1:
			var extra := Block.new()
			at = _read_block(d, at, extra)
			if at < 0:
				error = path + ": a later block does not fit"
				return false
		# There is no length field, so an exact landing is the whole of the
		# evidence that the strides are right.
		if at != d.size():
			error = "%s: walk ended at %d of %d" % [path, at, d.size()]
			block = null
			return false
		return true

	# ROBO1 and ROBO2 have no leading count: the first int32 is already the
	# matrix count and the file is one bare block.
	var bare := Block.new()
	var end := _read_block(d, 0, bare)
	if end == d.size():
		block = bare
		return true
	error = path + ": matches neither layout"
	return false


# ---------------------------------------------------------------- .skinanim
func load_anim(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		error = "no " + path
		return false
	anim = f.get_buffer(f.get_length())
	f.close()
	if anim.size() < 12:
		error = path + " is too short"
		return false

	anim_header = 12
	num_frames = anim.decode_s32(4)
	frame_size = anim.decode_s32(8)

	if frame_size <= 16 or 12 + num_frames * frame_size != anim.size():
		# **SINDEL_STANDARD has a 16-byte header and a count that is half the
		# truth.** Its first two words are 1.0f, then 422, then 1256; the file
		# is 1,060,080 bytes and 16 + 422 * 1256 is 530,048. What lands exactly
		# is 16 + 844 * 1256, so the frame SIZE is right, the header is 16, and
		# the count field holds half the frames.
		#
		# The C loader stops here: SKIN-FORMAT.md records the 16-byte reading
		# and leaves the halved count unresolved, and with 422 its own check
		# fails too -- so SINDEL does not load there either. Taking the frame
		# count from the file size instead is not a guess about the field: an
		# exact division by a frame size the header itself states is the same
		# kind of evidence every other stride in this file rests on.
		anim_header = 16
		frame_size = anim.decode_s32(12)
		if frame_size > 16 and (anim.size() - 16) % frame_size == 0:
			num_frames = (anim.size() - 16) / frame_size
		else:
			error = path + ": frames do not fit"
			return false

	# The bone count follows from the frame size and is NOT the skeleton's.
	# ROBO1 animates 20 of its 25 bones.
	anim_bones = (frame_size - 16) / 20
	return true


# -------------------------------------------------------------------- posing
class PaletteEntry extends RefCounted:
	var m := PackedFloat32Array()    ## 9, row-major
	var t := Vector3.ZERO


## GetMFromQuat2: a quaternion to a 3x3 at stride 3.
##
## **This is not Godot's `Basis(Quaternion)`, it is its TRANSPOSE**, because the
## engine works in the row-vector convention that `Xform2` and `MatrixMul2` use.
## Building the palette out of `Basis` instead put every rotation in inverted and
## laid Scorpion flat on his back in the graveyard -- an intact figure, rotated,
## which is exactly what a transposed rotation looks like when the whole skeleton
## is transposed consistently.
##
## The engine does not renormalise here, so this does not either.
static func _quat_m3(x: float, y: float, z: float, w: float) -> PackedFloat32Array:
	var m := PackedFloat32Array()
	m.resize(9)
	m[0] = 1.0 - 2.0 * (y * y + z * z)
	m[1] = 2.0 * (x * y + z * w)
	m[2] = 2.0 * (x * z - y * w)
	m[3] = 2.0 * (x * y - z * w)
	m[4] = 1.0 - 2.0 * (x * x + z * z)
	m[5] = 2.0 * (y * z + x * w)
	m[6] = 2.0 * (x * z + y * w)
	m[7] = 2.0 * (y * z - x * w)
	m[8] = 1.0 - 2.0 * (x * x + y * y)
	return m


## GetSlerpedQ, and **the engine's name is wrong on purpose**: there is no acos,
## no sin and no renormalisation in the original. It is a LERP with a
## shortest-arc sign flip. Substituting a real slerp -- which the first version
## here did, through `Quaternion.slerp` -- changes every in-between pose.
static func _blend_q(a: PackedFloat32Array, b: PackedFloat32Array,
					 t: float) -> PackedFloat32Array:
	var dot := a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
	var s := -1.0 if dot < 0.0 else 1.0
	var o := PackedFloat32Array()
	o.resize(4)
	for i in 4:
		o[i] = a[i] * (1.0 - t) + b[i] * s * t
	return o


## Build the palette for one interpolated moment between two frames.
func pose(frame_a: int, frame_b: int, t: float) -> Array:
	if bones.is_empty() or num_frames <= 0:
		return []
	frame_a = clampi(frame_a, 0, num_frames - 1)
	frame_b = clampi(frame_b, 0, num_frames - 1)

	var fa := anim_header + frame_a * frame_size
	var fb := anim_header + frame_b * frame_size

	var palette: Array = []
	palette.resize(bones.size())
	for i in bones.size():
		var e := PaletteEntry.new()
		e.m.resize(9)
		palette[i] = e

	# The root position is interpolated the same way, through LerpVector3.
	var root_pos := Vector3(
		_f(anim, fa + 4) * (1.0 - t) + _f(anim, fb + 4) * t,
		_f(anim, fa + 8) * (1.0 - t) + _f(anim, fb + 8) * t,
		_f(anim, fa + 12) * (1.0 - t) + _f(anim, fb + 12) * t)

	# **Depth-first, ONE ANIMATION FRAME CONSUMED PER BONE VISITED.** The
	# frames are indexed by visit order, not by bone index. Iterative because a
	# 128-deep recursion inside a frame loop is not worth it.
	var stack_bone := [root]
	var stack_parent := [-1]
	var order := 0

	while not stack_bone.is_empty():
		var bi: int = stack_bone.pop_back()
		var parent: int = stack_parent.pop_back()
		var n := order
		order += 1

		var r := PackedFloat32Array()
		r.resize(9)
		if n < anim_bones:
			var qa := PackedFloat32Array()
			var qb := PackedFloat32Array()
			qa.resize(4)
			qb.resize(4)
			for k in 4:
				qa[k] = _f(anim, fa + 16 + n * 20 + k * 4)
				qb[k] = _f(anim, fb + 16 + n * 20 + k * 4)
			var q := _blend_q(qa, qb, t)
			r = _quat_m3(q[0], q[1], q[2], q[3])
		else:
			# ROBO1 and ROBO2 ship fewer animated bones than skeleton bones.
			# Those tail bones genuinely have no rotation track, so identity is
			# the right fallback -- worth knowing rather than discovering as a
			# bent limb.
			r[0] = 1.0; r[4] = 1.0; r[8] = 1.0

		# The root takes its translation from the animation, everyone else from
		# the skeleton.
		var local_t := root_pos if n == 0 else bones[bi].offset

		var me: PaletteEntry = palette[bi]
		if parent < 0:
			me.m = r.duplicate()
			me.t = local_t
		else:
			var pa: PaletteEntry = palette[parent]
			# MatrixMul2, row-vector convention.
			for j in 3:
				for k in 3:
					me.m[j * 3 + k] = r[j * 3 + 0] * pa.m[0 * 3 + k] \
									+ r[j * 3 + 1] * pa.m[1 * 3 + k] \
									+ r[j * 3 + 2] * pa.m[2 * 3 + k]
			var tv := Vector3.ZERO
			for k in 3:
				tv[k] = local_t.x * pa.m[0 * 3 + k] \
					  + local_t.y * pa.m[1 * 3 + k] \
					  + local_t.z * pa.m[2 * 3 + k] \
					  + pa.t[k]
			me.t = tv

		# Push children in reverse so the pop order is slot order, which is
		# what makes the frame cursor line up with the original's walk. Nine
		# slots, or eight for the two 24-byte skeletons.
		for j in range(bones[bi].child.size() - 1, -1, -1):
			var c := bones[bi].child[j]
			if c >= 0 and c < bones.size():
				stack_bone.append(c)
				stack_parent.append(bi)

	return palette


## Skin one block's vertices. Returns [positions, greys].
##
## **The fast path, checked against `skin_reference` below.**
##
## This is the whole cost of an interpolated character: 5.1 ms of the 7.1 a pose
## took, measured by umk3_posebench.gd, which at two fighters was 14 ms a frame
## and 18 fps. The arithmetic is identical to the reference version -- what
## changed is how it is reached:
##
##   - the palette is flattened into one PackedFloat32Array first, so the inner
##     loop indexes a float array instead of reading `.m` and `.t` off a
##     RefCounted through a property lookup, twelve times a vertex
##   - x, y and z are written out rather than looped over
##   - the light is inlined, and **light 0 is skipped because its power is a
##     literal zero** -- `POWER0 * pow(d, EXP0)` cannot contribute. If that
##     value is ever changed the general path below takes over, so the shortcut
##     cannot quietly outlive its reason.
##
## umk3_skincheck.gd runs both over every frame and reports the largest
## disagreement. A faster version that is not the same version is not faster.
func skin(palette: Array) -> Array:
	var N := block.num_matrices
	var pos := PackedVector3Array()
	var col := PackedColorArray()
	pos.resize(N)
	col.resize(N)

	# 12 floats a bone: the 3x3, then the translation.
	var nb := palette.size()
	var pm := PackedFloat32Array()
	pm.resize(nb * 12)
	for j in nb:
		var e: PaletteEntry = palette[j]
		var o := j * 12
		for c in 9:
			pm[o + c] = e.m[c]
		pm[o + 9] = e.t.x
		pm[o + 10] = e.t.y
		pm[o + 11] = e.t.z

	var a := block.a
	var bn := block.b
	var wts := block.weights
	var idxs := block.indexes
	var d1: Vector3 = _Light.dir1()
	var d1x := d1.x
	var d1y := d1.y
	var d1z := d1.z
	var fill: float = _Light.fill
	var power1: float = _Light.POWER1
	var exp1: float = _Light.EXP1

	# The shortcut's own guard: if light 0 ever stops being a zero, the general
	# version takes over rather than silently dropping a term.
	if _Light.POWER0 != 0.0:
		return skin_reference(palette)

	for i in N:
		var idx := idxs[i]
		var px := 0.0
		var py := 0.0
		var pz := 0.0
		var nx := 0.0
		var ny := 0.0
		var nz := 0.0
		var ao := i * 12
		var wo := i * 4

		for k in 4:
			var bone := (idx >> (8 * k)) & 0xFF
			if bone == 0xFF or bone >= nb:
				continue
			var o := bone * 12
			var w := wts[wo + k]
			var ax := a[ao]
			var ay := a[ao + 1]
			var az := a[ao + 2]
			var bx := bn[ao]
			var by := bn[ao + 1]
			var bz := bn[ao + 2]
			ao += 3

			var m0 := pm[o]
			var m1 := pm[o + 1]
			var m2 := pm[o + 2]
			var m3 := pm[o + 3]
			var m4 := pm[o + 4]
			var m5 := pm[o + 5]
			var m6 := pm[o + 6]
			var m7 := pm[o + 7]
			var m8 := pm[o + 8]

			px += ax * m0 + ay * m3 + az * m6 + w * pm[o + 9]
			py += ax * m1 + ay * m4 + az * m7 + w * pm[o + 10]
			pz += ax * m2 + ay * m5 + az * m8 + w * pm[o + 11]

			nx += bx * m0 + by * m3 + bz * m6
			ny += bx * m1 + by * m4 + bz * m7
			nz += bx * m2 + by * m5 + bz * m8

		pos[i] = Vector3(px, py, pz)

		# LightVert, inlined. No ambient, the dot NEGATED, one pow, clamped to 1.
		var len := sqrt(nx * nx + ny * ny + nz * nz)
		var g := fill
		if len > 0.0:
			var d := -(nx * d1x + ny * d1y + nz * d1z) / len
			if d > 0.0:
				g += power1 * pow(d, exp1)
		if g > 1.0:
			g = 1.0
		col[i] = Color(g, g, g, 1.0)

	return [pos, col]


## The same thing written to be read rather than to be fast.
##
## This is the shape the engine's `DrawSkinnedMesh2` has, and it is what `skin`
## is checked against. Keep them in step: if one changes, the check fails, which
## is the point.
func skin_reference(palette: Array) -> Array:
	var N := block.num_matrices
	var pos := PackedVector3Array()
	var col := PackedColorArray()
	pos.resize(N)
	col.resize(N)

	for i in N:
		var idx := block.indexes[i]
		var p := Vector3.ZERO
		var nrm := Vector3.ZERO

		for k in 4:
			# **0xFF marks an unused influence.** Reading `indexes` as a signed
			# int32 is what made these look like negative numbers.
			var bone := (idx >> (8 * k)) & 0xFF
			if bone == 0xFF or bone >= palette.size():
				continue
			var e: PaletteEntry = palette[bone]
			var w := block.weights[i * 4 + k]
			var ao := i * 12 + k * 3
			# pos = SUM( A[i]*M3x3 + w[i]*T ), nrm = SUM( B[i]*M3x3 ).
			# A and B are ALREADY pre-multiplied by their weight, which is why
			# only the translation carries an explicit w.
			for c in 3:
				p[c] += block.a[ao] * e.m[0 * 3 + c] \
					  + block.a[ao + 1] * e.m[1 * 3 + c] \
					  + block.a[ao + 2] * e.m[2 * 3 + c] \
					  + w * e.t[c]
				nrm[c] += block.b[ao] * e.m[0 * 3 + c] \
						+ block.b[ao + 1] * e.m[1 * 3 + c] \
						+ block.b[ao + 2] * e.m[2 * 3 + c]

		pos[i] = p
		# Vertex colour IS the lit skinned normal, one grey. There is no
		# per-pixel lighting anywhere in this engine. **Characters really are
		# lit this way** -- unlike stages, whose bake is not decoded.
		var g := _Light.vert(nrm.normalized())
		col[i] = Color(g, g, g, 1.0)

	return [pos, col]


## Everything for one character, from the file stem.
func load_character(res_dir: String, stem: String) -> bool:
	error = ""
	if not load_bones(res_dir.path_join(stem + ".bones")):
		return false
	if not load_skin(res_dir.path_join(stem + ".skin")):
		return false
	if not load_anim(res_dir.path_join(stem + ".skinanim")):
		return false
	return true
