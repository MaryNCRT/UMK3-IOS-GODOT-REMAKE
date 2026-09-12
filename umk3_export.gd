## Write the characters and the stages out as files Blender can open.
##
##     godot --headless --path <project> --script umk3/umk3_export.gd -- \
##           [--out DIR] [--char NAME] [--stages] [--stage N] [--blender EXE]
##
## Characters come out **rigged**: a real skeleton, one bone per bone of the
## `.bones` file, skin weights out of the `.skin`, and one animation clip per
## entry of the engine's own animation table. Stages come out as the geometry
## their `.meshset` holds, placed by their `.scene`.
##
## ## Why GLB and not FBX
##
## Godot can WRITE glTF and cannot write FBX -- there is no FBX exporter in the
## engine, and its FBX support is an importer that shells out to a converter.
## Blender opens `.glb` natively, with the armature, the weights, the animation
## clips and the texture, so nothing is lost by going that way.
##
## If Blender is installed, `--blender <blender.exe>` runs it afterwards to turn
## each `.glb` into a `.fbx` beside it, which is the only honest way to produce
## one. **Blender was not installed on the machine this was written on**, so
## that step has not been run here; the script it writes is left in the output
## folder so it can be.
##
## ## The rig is SOLVED FOR, and it is checked
##
## A `.skin` does not store a bind pose. It stores, per vertex and per
## influence, the vertex ALREADY multiplied by its weight in that bone's local
## frame -- which is what `skin_reference` sums. A rig needs the other shape of
## the same fact: one rest position per vertex, one inverse bind per bone, and
## weights.
##
## Dividing the stored triple by its weight gives the vertex in that bone's
## local frame. Putting those back into one model space needs each bone's bind
## transform, and **the file does not contain it.** The first version of this
## assumed the bind pose was the skeleton's offsets with no rotation, which is
## wrong by half a metre; umk3_bindprobe2.gd then showed that no animation
## frame is the bind pose either -- the best of the 344 still disagrees by 11
## units.
##
## So it is recovered. 585 of Scorpion's 1,278 vertices are shared between two
## or more bones, and a shared vertex is one point written down twice: in two
## different bones' frames. Three such points shared by a pair of bones fix the
## rigid transform between those two frames exactly, with no fitting and no
## SVD -- build an orthonormal frame from the three points on each side and
## compose. Starting at the root and spreading to whichever bone already shares
## three points with a solved one recovers the whole skeleton.
##
## A bone that shares nothing is unconstrained and it does not matter: every
## one of its vertices has a single influence, so any pose for it skins
## correctly. Those are hung off the parent by their own offset so the rest
## pose still looks like a person.
##
## **The check is the residual**, measured over every vertex and printed. A rig
## that does not reproduce the original skinning is a rig that should not be
## shipped, and this says so in a number rather than in a hope.
##
## ## No game data ships here
extends SceneTree

const _Skin := preload("res://umk3/umk3_skin.gd")
const _MeshSet := preload("res://umk3/umk3_meshset.gd")
const _Textures := preload("res://umk3/umk3_textures.gd")
const _Stage := preload("res://umk3/umk3_stage.gd")
const _StageList := preload("res://umk3/umk3_stagelist.gd")
const _Paths := preload("res://umk3/umk3_paths.gd")
const _Ani := preload("res://umk3/umk3_scorpion_ani.gd")
const _Fighter := preload("res://umk3/umk3_fighter.gd")

## The engine's animation clock, the same numbers the fight runs on: one
## displayed frame every `RATE` ticks of an `HZ` second. See umk3_fight.gd --
## six is what `stance_setup` sets and what every attack inherits, because
## nothing in the attack path ever calls `init_anirate`.
const RATE := 6
const HZ := 60.0

var out_dir := "res://export"
var res_dir := ""
var chars: Array[String] = []
var do_stages := false
var one_stage := -1
var blender := ""
var report: Array[String] = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--out":
				out_dir = args[i + 1]
				i += 1
			"--char":
				chars.append(args[i + 1])
				i += 1
			"--stage":
				one_stage = int(args[i + 1])
				i += 1
			"--stages":
				do_stages = true
			"--blender":
				blender = args[i + 1]
				i += 1
			"--res":
				res_dir = args[i + 1]
				i += 1
		i += 1
	if chars.is_empty() and not do_stages and one_stage < 0:
		chars.append("SCORPION_STANDARD")

	res_dir = _Paths.resolve(res_dir)
	if res_dir == "":
		printerr("[export] no game data -- run umk3_bundle.gd first")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("characters"))
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("stages"))

	var textures = _Textures.new(res_dir)
	for c in chars:
		_export_character(c, textures)
	if do_stages:
		for s in _StageList.STAGES.size():
			_export_stage(s, textures)
	elif one_stage >= 0:
		_export_stage(one_stage, textures)

	print("\n".join(report))
	_write_blender_script()
	if blender != "":
		_run_blender()
	quit(0)


# ------------------------------------------------------------------ character
## Depth-first, children in slot order -- the SAME walk `pose()` does, so a
## Godot bone index and the animation's slot index are the same number.
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


## Recover each bone's bind transform from the vertices the bones share.
##
## Returns [Array of Transform3D (global bind, indexed by SLOT), how many were
## solved rather than guessed].
##
## The root is the frame everything else is expressed in. From there this keeps
## sweeping: any unsolved bone that shares three well-spread vertices with a
## solved one gets its transform from those three, exactly. A bone that never
## shares anything keeps its parent's rotation and its own offset, which is
## correct to skin with -- all of its vertices have one influence -- and looks
## right standing still.
func _solve_bind(skin, order: PackedInt32Array, slot_of: Dictionary,
		parent_of: Dictionary, units: float) -> Array:
	var b = skin.block
	var n := order.size()

	# Per slot: vertex index -> the vertex in that bone's own frame.
	var pts: Array = []
	pts.resize(n)
	for s in n:
		pts[s] = {}
	for i in b.num_matrices:
		var idx: int = b.indexes[i]
		for k in 4:
			var bone := (idx >> (8 * k)) & 0xFF
			var w: float = b.weights[i * 4 + k]
			if bone == 0xFF or not slot_of.has(bone) or w <= 0.0001:
				continue
			var ao: int = i * 12 + k * 3
			pts[int(slot_of[bone])][i] = 				Vector3(b.a[ao], b.a[ao + 1], b.a[ao + 2]) / w * units

	# A provisional placement: offsets only, no rotation. It anchors each
	# island of bones and is what an unshared bone keeps.
	var prov: Array = []
	prov.resize(n)
	for s in n:
		var pslot: int = parent_of[s]
		var off: Vector3 = Vector3.ZERO if s == 0 			else skin.bones[order[s]].offset * units
		var base: Transform3D = prov[pslot] if pslot >= 0 else Transform3D.IDENTITY
		prov[s] = base * Transform3D(Basis.IDENTITY, off)

	var out: Array = []
	out.resize(n)
	var known := PackedByteArray()
	known.resize(n)
	var solved := 0

	# **One island at a time.** The root carries no vertices in this skeleton,
	# so seeding only from it solved nothing: the sweep has to be able to start
	# again wherever it runs out. Each island is anchored by its highest bone's
	# provisional place, which keeps the figure the right way up, and every
	# other bone in it is then exact.
	for seed in n:
		if known[seed]:
			continue
		out[seed] = prov[seed]
		known[seed] = 1
		var grew := true
		while grew:
			grew = false
			for s in n:
				if known[s]:
					continue
				for other in n:
					if not known[other]:
						continue
					var tr = _align(pts[s], pts[other], out[other])
					if tr == null:
						continue
					out[s] = tr
					known[s] = 1
					solved += 1
					grew = true
					break

	return [out, solved]


## The rigid transform that carries `mine` into the world, given that `theirs`
## is already placed by `g`. Null when the two share fewer than three points
## that are actually spread out.
##
## Three corresponding points fix a rigid transform: build an orthonormal frame
## from them on each side and compose. No least squares, because the data is
## not noisy -- these are the same numbers written twice.
static func _align(mine: Dictionary, theirs: Dictionary,
		g: Transform3D):
	var src: Array[Vector3] = []
	var dst: Array[Vector3] = []
	for v in mine:
		if theirs.has(v):
			src.append(mine[v])
			dst.append(g * (theirs[v] as Vector3))
	if src.is_empty():
		return null

	# The widest pair, then the point furthest off that line: the best
	# conditioned triangle available rather than the first one found.
	var i1 := -1
	var best := 0.0
	for i in range(1, src.size()):
		var d: float = (src[i] - src[0]).length()
		if d > best:
			best = d
			i1 = i
	var axis := Vector3.ZERO
	var i2 := -1
	if i1 >= 0 and best > 1e-4:
		axis = (src[i1] - src[0]).normalized()
		best = 0.0
		for i in range(1, src.size()):
			var off: Vector3 = src[i] - src[0]
			var perp: float = (off - axis * off.dot(axis)).length()
			if perp > best:
				best = perp
				i2 = i
		if best < 1e-4:
			i2 = -1

	# **Three well-spread shared points give the answer outright.** Fewer
	# leaves some of the rotation free, and a free rotation is genuinely free:
	# the vertices it moves all have a single influence, so any choice skins
	# correctly. What is NOT free is the part the shared points do fix, and
	# taking the rest from the bone already placed is what keeps the rest pose
	# from folding a limb somewhere silly.
	var basis: Basis = g.basis
	if i2 >= 0:
		var fs = _frame(src[0], src[i1], src[i2])
		var fd = _frame(dst[0], dst[i1], dst[i2])
		if fs == null or fd == null:
			return null
		basis = (fd as Basis) * (fs as Basis).transposed()
	elif i1 >= 0:
		# Two points: only the twist about the line through them is free.
		var from := (basis * (src[i1] - src[0])).normalized()
		var to := (dst[i1] - dst[0]).normalized()
		var cross := from.cross(to)
		if cross.length() > 1e-6:
			basis = Basis(cross.normalized(),
				acos(clampf(from.dot(to), -1.0, 1.0))) * basis
		elif from.dot(to) < 0.0:
			basis = Basis(basis.y.normalized(), PI) * basis
	return Transform3D(basis, dst[0] - basis * src[0])


## An orthonormal basis from three points, columns [u, v, w].
static func _frame(a: Vector3, b: Vector3, c: Vector3):
	var u := (b - a)
	if u.length() < 1e-6:
		return null
	u = u.normalized()
	var t := c - a
	var w := u.cross(t)
	if w.length() < 1e-6:
		return null
	w = w.normalized()
	return Basis(u, w.cross(u), w)


func _export_character(stem: String, textures) -> void:
	var skin = _Skin.new()
	if not skin.load_character(res_dir, stem):
		report.append("%s: %s" % [stem, skin.error])
		return

	var order := _order(skin)
	var slot_of := {}                      # bone index -> slot
	var parent_of := {}                    # slot -> parent slot
	for s in order.size():
		slot_of[order[s]] = s
		parent_of[s] = -1
	for bi in skin.bones.size():
		for c in skin.bones[bi].child:
			if c >= 0 and c < skin.bones.size() and slot_of.has(c):
				parent_of[slot_of[c]] = slot_of[bi]

	# **The scale, so a fighter comes out 1.8 m tall in Blender too.** The same
	# two numbers the fight uses: the format's own unit, then the stance
	# measured and divided into 1.8.
	var m := _measure(skin)
	var units: float = _Fighter.PLAYER_TO_SCENE \
		* (_Fighter.FIGHTER_METRES / m if m > 0.0 else 1.0)

	# The bind pose, recovered from the vertices the bones share. See the top
	# of this file.
	var bind := _solve_bind(skin, order, slot_of, parent_of, units)
	var rest_global: Array = bind[0]
	var solved: int = bind[1]

	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	for s in order.size():
		skel.add_bone("bone_%03d" % s)
		var p: int = parent_of[s]
		var local: Transform3D = rest_global[s]
		if p >= 0:
			skel.set_bone_parent(s, p)
			local = (rest_global[p] as Transform3D).affine_inverse() * local
		# Rest EQUALS bind, so the armature in Blender opens standing in the
		# pose the weights were authored against rather than folded up.
		skel.set_bone_rest(s, local)
		skel.set_bone_pose_position(s, local.origin)
		skel.set_bone_pose_rotation(s, local.basis.get_rotation_quaternion())

	var built := _build_mesh(skin, slot_of, rest_global, units, stem, textures)
	var mesh: ArrayMesh = built[0]
	report.append("%s: %d bones (%d solved from shared vertices), %d vertices"
		% [stem, order.size(), solved, mesh.surface_get_array_len(0)])
	# A centimetre on a 1.8 m figure is float32 rounding on the divide-by-
	# weight, not a wrong rig -- umk3_checkglb.gd makes the stronger check, by
	# animating the exported skeleton and comparing against umk3_skin.gd.
	report.append("   rig residual: worst %.4f m, median %.4f m  (%s)"
		% [built[1], built[2],
		"good" if float(built[1]) < 0.01 else "CHECK THIS"])

	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mesh
	var sk := Skin.new()
	for s in order.size():
		sk.add_named_bind("bone_%03d" % s,
			(rest_global[s] as Transform3D).affine_inverse())
	mi.skin = sk
	skel.add_child(mi)
	mi.skeleton = mi.get_path_to(skel)

	var root := Node3D.new()
	root.name = stem
	root.add_child(skel)

	var lib := AnimationLibrary.new()
	var clips := 0
	for id in _Ani.ANI.size():
		var a: Array = _Ani.ANI[id]
		if a.is_empty():
			continue
		lib.add_animation("%03d_%s" % [id, a[0]],
			_clip(skin, order, units, a[2], a[1]))
		clips += 1
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	ap.add_animation_library("", lib)
	root.add_child(ap)

	for n in root.get_children():
		_own(n, root)

	var path := out_dir.path_join("characters").path_join(stem + ".glb")
	_write_glb(root, path)
	report.append("   -> %s   %d clips" % [path, clips])
	root.queue_free()


## The stance's height in scene units, which is what the fight divides into
## 1.8 m. See umk3_fighter.gd's measure(): frame 216, not frame 0.
func _measure(skin) -> float:
	var r: Array = skin.skin(skin.pose(216, 216, 0.0))
	var pos: PackedVector3Array = r[0]
	if pos.is_empty():
		return 0.0
	var lo := pos[0].y
	var hi := lo
	for p in pos:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	return (hi - lo) * _Fighter.PLAYER_TO_SCENE


## The mesh, with weights -- and the check that the weights describe the same
## model the CPU skinner draws. Returns [ArrayMesh, worst disagreement].
func _build_mesh(skin, slot_of: Dictionary, rest_global: Array,
		units: float, stem: String, textures) -> Array:
	var b = skin.block
	var worst := 0.0
	var spread := PackedFloat32Array()

	# One rest position, one normal and one set of four influences per SKINNED
	# vertex, before the per-corner expansion.
	var rest := PackedVector3Array()
	var norm := PackedVector3Array()
	var bones4 := PackedInt32Array()
	var wts4 := PackedFloat32Array()
	rest.resize(b.num_matrices)
	norm.resize(b.num_matrices)
	bones4.resize(b.num_matrices * 4)
	wts4.resize(b.num_matrices * 4)

	for i in b.num_matrices:
		var idx: int = b.indexes[i]
		var p := Vector3.ZERO
		var n := Vector3.ZERO
		var seen: Array[Vector3] = []
		for k in 4:
			var bone := (idx >> (8 * k)) & 0xFF
			var w: float = b.weights[i * 4 + k]
			var slot := int(slot_of.get(bone, 0))
			bones4[i * 4 + k] = slot if bone != 0xFF else 0
			wts4[i * 4 + k] = 0.0
			if bone == 0xFF or bone >= skin.bones.size() or w <= 0.0:
				continue
			wts4[i * 4 + k] = w
			var ao: int = i * 12 + k * 3
			# `a` is the vertex PRE-MULTIPLIED by its weight, in the bone's own
			# frame. Undo the weight and put it back into model space.
			var local := Vector3(b.a[ao], b.a[ao + 1], b.a[ao + 2]) / w * units
			var world: Vector3 = (rest_global[slot] as Transform3D) * local
			seen.append(world)
			p += world * w
			n += Vector3(b.b[ao], b.b[ao + 1], b.b[ao + 2])
		var far := 0.0
		for s in seen:
			far = maxf(far, (s - seen[0]).length())
		if seen.size() > 1:
			spread.append(far)
		worst = maxf(worst, far)
		rest[i] = p
		norm[i] = n.normalized() if n.length_squared() > 0.0 else Vector3.UP

	# The per-corner expansion, the same one the fight uses: a corner is only
	# distinct when its position index AND its UV differ.
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var uv := PackedVector2Array()
	var bn := PackedInt32Array()
	var wt := PackedFloat32Array()
	var idxbuf := PackedInt32Array()
	var seen_map := {}
	for i in b.num_verts * 3:
		var k: int = b.tri[i]
		if k >= b.num_matrices:
			k = 0
		var t: Vector2 = b.uv[i]
		var key := "%d|%.6f|%.6f" % [k, t.x, t.y]
		var at: int = seen_map.get(key, -1)
		if at < 0:
			at = v.size()
			seen_map[key] = at
			v.append(rest[k])
			nn.append(norm[k])
			uv.append(t)
			for c in 4:
				bn.append(bones4[k * 4 + c])
				wt.append(wts4[k * 4 + c])
		idxbuf.append(at)

	var arrays := []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = v
	arrays[ArrayMesh.ARRAY_NORMAL] = nn
	arrays[ArrayMesh.ARRAY_TEX_UV] = uv
	arrays[ArrayMesh.ARRAY_BONES] = bn
	arrays[ArrayMesh.ARRAY_WEIGHTS] = wt
	arrays[ArrayMesh.ARRAY_INDEX] = idxbuf

	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# The body texture, named by mesh 0 of the character's own meshset -- the
	# `.skin` does not carry one.
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ms := _MeshSet.new()
	if ms.load_file(res_dir.path_join(stem + ".meshset")) and ms.meshes.size() > 0:
		var tex = textures.get_texture(ms.meshes[0].texture)
		if tex:
			mat.albedo_texture = tex
	am.surface_set_material(0, mat)
	spread.sort()
	var med: float = spread[spread.size() / 2] if spread.size() > 0 else 0.0
	return [am, worst, med]


## One clip out of one of the engine's streams.
##
## The times are the engine's: a displayed frame lasts `RATE` ticks of an `HZ`
## second. A looping stream is marked looping, which is what the stream's own
## opcode 1 -- a jump back to its start -- means.
func _clip(skin, order: PackedInt32Array, units: float, frames: Array,
		loops: bool) -> Animation:
	var a := Animation.new()
	var step := float(RATE) / HZ
	a.length = maxf(step * frames.size(), step)
	a.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE

	# **A position track per bone, not just for the root.**
	#
	# The rest pose of this skeleton is the BIND pose -- solved for, so the
	# model opens undeformed -- and the bind pose is not where the animation
	# puts the bones. `pose()` gives every bone the translation out of
	# `.bones` and only the root one out of the animation, so a clip that
	# keyed rotation alone left every bone sitting at its bind offset and the
	# figure came apart: 1.46 m of error against the engine's own skinner,
	# which is how this was found.
	var pos := PackedInt32Array()
	var rot := PackedInt32Array()
	for s in order.size():
		var tp := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(tp, "Skeleton3D:bone_%03d" % s)
		pos.append(tp)
		var tr := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(tr, "Skeleton3D:bone_%03d" % s)
		rot.append(tr)

	for f in frames.size():
		var t := step * f
		var frame: int = clampi(int(frames[f]), 0, skin.num_frames - 1)
		var base: int = skin.anim_header + frame * skin.frame_size
		var root_pos := Vector3(
			skin.anim.decode_float(base + 4),
			skin.anim.decode_float(base + 8),
			skin.anim.decode_float(base + 12)) * units
		for s in order.size():
			a.position_track_insert_key(pos[s], t, root_pos if s == 0
				else skin.bones[order[s]].offset * units)
			var q := Quaternion.IDENTITY
			if s < skin.anim_bones:
				var o: int = base + 16 + s * 20
				var raw := Quaternion(skin.anim.decode_float(o),
					skin.anim.decode_float(o + 4),
					skin.anim.decode_float(o + 8),
					skin.anim.decode_float(o + 12))
				if raw.length_squared() > 0.0:
					q = raw.normalized()
			a.rotation_track_insert_key(rot[s], t, q)
	return a


# --------------------------------------------------------------------- stage
func _export_stage(which: int, textures) -> void:
	var stem: String = _StageList.STAGES[which]
	var st = _Stage.new()
	if not st.build(res_dir, stem, 0):
		report.append("%s: %s" % [stem, st.error])
		return
	get_root().add_child(st)
	var path := out_dir.path_join("stages").path_join(stem + ".glb")
	_write_glb(st, path)
	report.append("%s: %d meshes -> %s"
		% [stem, st.meshset.meshes.size(), path])
	get_root().remove_child(st)
	st.queue_free()


# --------------------------------------------------------------------- output
static func _own(n: Node, root: Node) -> void:
	n.owner = root
	for c in n.get_children():
		_own(c, root)


func _write_glb(root: Node, path: String) -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err != OK:
		report.append("   append_from_scene failed: %d" % err)
		return
	err = doc.write_to_filesystem(state, ProjectSettings.globalize_path(path))
	if err != OK:
		report.append("   write failed: %d" % err)


## The Blender side of the FBX step, written out whether or not it is run.
func _write_blender_script() -> void:
	var lines := [
		"# Written by umk3/umk3_export.gd.",
		"#",
		"#     blender --background --python glb_to_fbx.py -- <in.glb> <out.fbx>",
		"#",
		"# Godot has no FBX exporter, so this is a CONVERSION and not a second",
		"# export: Blender reads the glTF the exporter wrote and saves FBX.",
		"import bpy, sys",
		"argv = sys.argv[sys.argv.index('--') + 1:]",
		"bpy.ops.wm.read_factory_settings(use_empty=True)",
		"bpy.ops.import_scene.gltf(filepath=argv[0])",
		"bpy.ops.export_scene.fbx(filepath=argv[1], path_mode='COPY',",
		"                         embed_textures=True, add_leaf_bones=False,",
		"                         bake_anim_use_nla_strips=False,",
		"                         bake_anim_use_all_actions=True)",
		"",
	]
	var f := FileAccess.open(out_dir.path_join("glb_to_fbx.py"),
		FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines))
		f.close()


func _run_blender() -> void:
	var gscript := ProjectSettings.globalize_path(
		out_dir.path_join("glb_to_fbx.py"))
	for sub in ["characters", "stages"]:
		var d := DirAccess.open(out_dir.path_join(sub))
		if d == null:
			continue
		for name in d.get_files():
			if not name.ends_with(".glb"):
				continue
			var src := ProjectSettings.globalize_path(
				out_dir.path_join(sub).path_join(name))
			var dst := src.get_basename() + ".fbx"
			var o := []
			var code := OS.execute(blender, ["--background", "--python",
				gscript, "--", src, dst], o, true)
			print("[export] blender %s -> %s (exit %d)" % [name, dst, code])
