## Does the exported rig deform like the engine?
##
## The exporter prints the residual of its own bind-pose solve, which says the
## rig is self-consistent in the REST pose. That is not the same claim as "it
## animates the same way". This makes the stronger one: load the `.glb` back,
## drive its skeleton with a real animation frame, skin it by hand the way the
## GPU would, and compare every vertex against `umk3_skin.gd`'s own answer --
## the function the fight has been drawing with all along.
##
##     godot --headless --path <project> --script umk3/umk3_checkglb.gd \
##           [-- --frame 216]
##
## ## No game data ships here
extends SceneTree

const _Skin := preload("res://umk3/umk3_skin.gd")
const _Paths := preload("res://umk3/umk3_paths.gd")
const _Fighter := preload("res://umk3/umk3_fighter.gd")

const GLB := "res://export/characters/SCORPION_STANDARD.glb"


func _init() -> void:
	var frame := 216
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--frame":
			frame = int(args[i + 1])

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var bytes := FileAccess.get_file_as_bytes(GLB)
	if bytes.is_empty():
		printerr("no %s -- run umk3_export.gd first" % GLB)
		quit(2)
		return
	if doc.append_from_buffer(bytes, "", state) != OK:
		printerr("could not read %s" % GLB)
		quit(2)
		return
	var root := doc.generate_scene(state)
	var skel: Skeleton3D = root.find_child("Skeleton3D", true, false)
	var mi: MeshInstance3D = root.find_child("Body", true, false)
	if skel == null or mi == null:
		printerr("no skeleton or mesh in the glb")
		quit(2)
		return

	var res_dir := _Paths.resolve("")
	var skin = _Skin.new()
	if not skin.load_character(res_dir, "SCORPION_STANDARD"):
		printerr(skin.error)
		quit(2)
		return

	# Drive the rig the way the fight drives it: the root's animated position,
	# and one quaternion per bone in the animation's own slot order.
	var m := _measure(skin)
	var units: float = _Fighter.PLAYER_TO_SCENE \
		* (_Fighter.FIGHTER_METRES / m if m > 0.0 else 1.0)
	var base: int = skin.anim_header + frame * skin.frame_size
	var order := _order(skin)
	for s in skel.get_bone_count():
		# Every bone takes its translation from `.bones`; only the root takes
		# one from the animation. The bind pose this rig rests in is somewhere
		# else entirely, so leaving the others alone is what tore the model up.
		skel.set_bone_pose_position(s, Vector3(
			skin.anim.decode_float(base + 4),
			skin.anim.decode_float(base + 8),
			skin.anim.decode_float(base + 12)) * units if s == 0
			else skin.bones[order[s]].offset * units)
		if s >= skin.anim_bones:
			continue
		var o: int = base + 16 + s * 20
		var q := Quaternion(skin.anim.decode_float(o),
			skin.anim.decode_float(o + 4),
			skin.anim.decode_float(o + 8),
			skin.anim.decode_float(o + 12))
		if q.length_squared() > 0.0:
			skel.set_bone_pose_rotation(s, q.normalized())

	# Skin it by hand: the same sum the GPU does.
	var sk: Skin = mi.skin
	var arrays: Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bn: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var wt: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var xf: Array[Transform3D] = []
	for s in skel.get_bone_count():
		xf.append(skel.get_bone_global_pose(s) * sk.get_bind_pose(s))

	# And the engine's own answer for the same frame.
	var want: PackedVector3Array = skin.skin(skin.pose(frame, frame, 0.0))[0]

	var worst := 0.0
	var sum := 0.0
	for i in v.size():
		var p := Vector3.ZERO
		for k in 4:
			var w: float = wt[i * 4 + k]
			if w > 0.0:
				p += (xf[bn[i * 4 + k]] * v[i]) * w
		# Which engine vertex this corner came from is not stored, so compare
		# against the nearest -- with an exact rig the nearest IS the one.
		var d := 1e30
		for j in want.size():
			var q: Vector3 = want[j] * units
			var e: float = (q - p).length()
			if e < d:
				d = e
		worst = maxf(worst, d)
		sum += d
	print("frame %d: %d vertices, worst %.5f m, mean %.5f m -- %s"
		% [frame, v.size(), worst, sum / maxf(v.size(), 1),
		"MATCHES the engine" if worst < 0.01 else "DOES NOT MATCH"])
	quit(0)


## The same depth-first walk the exporter and `pose()` use.
func _order(skin) -> PackedInt32Array:
	var out := PackedInt32Array()
	var stack: Array[int] = [skin.root]
	while not stack.is_empty():
		var bi: int = stack.pop_back()
		out.append(bi)
		for j in range(skin.bones[bi].child.size() - 1, -1, -1):
			var c: int = skin.bones[bi].child[j]
			if c >= 0 and c < skin.bones.size():
				stack.append(c)
	return out


func _measure(skin) -> float:
	var pos: PackedVector3Array = skin.skin(skin.pose(216, 216, 0.0))[0]
	if pos.is_empty():
		return 0.0
	var lo := pos[0].y
	var hi := lo
	for p in pos:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	return (hi - lo) * _Fighter.PLAYER_TO_SCENE
