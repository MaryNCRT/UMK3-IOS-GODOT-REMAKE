## Which pose were these vertices bound in?
##
##     godot --headless --path <project> --script umk3/umk3_bindprobe.gd -- \
##           <res dir> SCORPION_STANDARD
##
## The `.skin` stores each vertex once per influencing bone, in that bone's own
## frame (`A[k]`, pre-multiplied by the weight). For Godot to skin it, all of
## those have to be reduced to ONE position in mesh space -- and that is only
## possible if every influencing bone agrees on where the vertex sits in some
## reference pose. That pose is the bind pose.
##
## The obvious guess is the skeleton with identity rotations. That guess is
## WRONG here: the bones disagree by up to 39.5 units out of a 140-unit figure.
## So this walks every animation frame and reports which one the bones agree in.
## If one of them comes out near zero, that frame IS the bind pose and the
## importer can use it; if none does, the data does not admit a single bind pose
## and a skinned Godot mesh cannot reproduce it exactly.
##
## Measuring which, rather than assuming either, is the whole point of this file.
extends SceneTree

const UMK3Skin := preload("res://umk3/umk3_skin.gd")

var skin = null


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: ... -- <res dir> <NAME>")
		quit(2)
		return
	skin = UMK3Skin.new()
	if not skin.load_character(args[0], args[1]):
		printerr(skin.error)
		quit(1)
		return

	# A sample is enough to rank poses, and 1,278 vertices times 344 frames is
	# not. Every 17th vertex, which is 76 of them spread over the whole body.
	var sample: Array[int] = []
	var i := 0
	while i < skin.block.num_matrices:
		sample.append(i)
		i += 17

	print("identity rest: %s" % _score(_identity_palette(), sample))

	var best := -1
	var best_score := INF
	for f in skin.num_frames:
		var s := _score(skin.pose(f, f, 0.0), sample)
		if s < best_score:
			best_score = s
			best = f
	print("best animation frame: %d, worst disagreement %.4f" % [best, best_score])

	# **The claim spread is a proxy. What matters is the error on screen.**
	#
	# So: take a candidate bind pose, reduce every vertex to the one position
	# the engine itself puts it at in that pose, then skin THAT the way Godot
	# would in other poses and compare against what the engine produces. That
	# number is how wrong the imported model would look, in scene units, on a
	# figure 140 units tall.
	for bind in [-1, best, 216]:
		var pal_bind: Array = _identity_palette() if bind < 0 \
			else skin.pose(bind, bind, 0.0)
		var report := _final_error(pal_bind, sample)
		print("bind %s: mean %.3f, worst %.3f units of %.1f tall"
			% ["identity" if bind < 0 else str(bind), report[0], report[1], 140.1])
	quit(0)


## How far Godot's skinning would land from the engine's, given a bind pose.
func _final_error(pal_bind: Array, sample: Array[int]) -> Array:
	var b = skin.block
	var total := 0.0
	var count := 0
	var worst := 0.0

	# The rest position IS the engine's own output in the bind pose: whatever
	# the bones disagree about, the blend they produce is a real point.
	var rest := {}
	var inv := {}
	for i in sample:
		var p := Vector3.ZERO
		var idx: int = b.indexes[i]
		for k in 4:
			var bone := (idx >> (8 * k)) & 0xFF
			if bone == 0xFF or bone >= pal_bind.size():
				continue
			var w: float = b.weights[i * 4 + k]
			var e = pal_bind[bone]
			var ao := i * 12 + k * 3
			for c in 3:
				p[c] += b.a[ao] * e.m[0 * 3 + c] \
					+ b.a[ao + 1] * e.m[1 * 3 + c] \
					+ b.a[ao + 2] * e.m[2 * 3 + c] + w * e.t[c]
		rest[i] = p

	# Every 31st frame: enough spread to catch a pose that breaks.
	var f := 0
	while f < skin.num_frames:
		var pal: Array = skin.pose(f, f, 0.0)
		for i in sample:
			var idx: int = b.indexes[i]
			var engine := Vector3.ZERO
			var godot := Vector3.ZERO
			for k in 4:
				var bone := (idx >> (8 * k)) & 0xFF
				if bone == 0xFF or bone >= pal.size():
					continue
				var w: float = b.weights[i * 4 + k]
				var e = pal[bone]
				var eb = pal_bind[bone]
				var ao := i * 12 + k * 3
				for c in 3:
					engine[c] += b.a[ao] * e.m[0 * 3 + c] \
						+ b.a[ao + 1] * e.m[1 * 3 + c] \
						+ b.a[ao + 2] * e.m[2 * 3 + c] + w * e.t[c]
				# Godot: undo the bind pose, then apply this one.
				var local := _untransform(eb, rest[i])
				for c in 3:
					godot[c] += w * (local.x * e.m[0 * 3 + c]
						+ local.y * e.m[1 * 3 + c]
						+ local.z * e.m[2 * 3 + c] + e.t[c])
			var d: float = (engine - godot).length()
			total += d
			count += 1
			worst = maxf(worst, d)
		f += 31
	return [total / maxf(float(count), 1.0), worst]


## The inverse of a palette entry applied to a point: the engine's matrices are
## row-vector and orthonormal, so the inverse rotation is the transpose.
func _untransform(e, p: Vector3) -> Vector3:
	var d: Vector3 = p - e.t
	return Vector3(
		d.x * e.m[0] + d.y * e.m[1] + d.z * e.m[2],
		d.x * e.m[3] + d.y * e.m[4] + d.z * e.m[5],
		d.x * e.m[6] + d.y * e.m[7] + d.z * e.m[8])


func _identity_palette() -> Array:
	var pal: Array = []
	pal.resize(skin.bones.size())
	var stack_bone := [skin.root]
	var stack_parent := [-1]
	while not stack_bone.is_empty():
		var bi: int = stack_bone.pop_back()
		var pa: int = stack_parent.pop_back()
		var e = UMK3Skin.PaletteEntry.new()
		e.m = PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1])
		e.t = Vector3.ZERO if pa < 0 else \
			skin.bones[bi].offset + (pal[pa] as UMK3Skin.PaletteEntry).t
		pal[bi] = e
		for j in range(skin.bones[bi].child.size() - 1, -1, -1):
			var c: int = skin.bones[bi].child[j]
			if c >= 0 and c < skin.bones.size():
				stack_bone.append(c)
				stack_parent.append(bi)
	return pal


## The largest distance between two bones' opinions of where a vertex is.
func _score(pal: Array, sample: Array[int]) -> float:
	var b = skin.block
	var worst := 0.0
	for i in sample:
		var idx: int = b.indexes[i]
		var claims: Array[Vector3] = []
		for k in 4:
			var bone := (idx >> (8 * k)) & 0xFF
			if bone == 0xFF or bone >= pal.size():
				continue
			var w: float = b.weights[i * 4 + k]
			if w <= 0.0001:
				continue
			var e = pal[bone]
			var ao := i * 12 + k * 3
			# The bone's own claim: its local position put through that bone's
			# matrix, undoing the weight.
			var local := Vector3(b.a[ao] / w, b.a[ao + 1] / w, b.a[ao + 2] / w)
			var p := Vector3.ZERO
			for c in 3:
				p[c] = local.x * e.m[0 * 3 + c] + local.y * e.m[1 * 3 + c] \
					+ local.z * e.m[2 * 3 + c] + e.t[c]
			claims.append(p)
		for c in claims:
			worst = maxf(worst, (c - claims[0]).length())
	return worst
