## Import one character into the project as a native Godot scene.
##
##     godot --headless --path <project> --script umk3/umk3_import.gd -- \
##           <res dir> SCORPION_STANDARD
##
## Writes `res://assets/characters/<NAME>/` holding a `.tscn` with a Skeleton3D,
## a skinned mesh, the body texture and one Animation per named clip out of the
## character's frame list. After this the model opens in the editor like any
## other asset: bones are selectable, animations are in the AnimationPlayer, and
## nothing has to be re-read from the game at run time.
##
## ## Why this exists at all
##
## The run-time path (umk3_skin.gd + umk3_fighter.gd) skins on the CPU in
## GDScript at 5.3 ms a pose, which is why it caches whole frames and cannot
## interpolate between them. Handing Godot a real skinned mesh moves that work
## to the GPU: the fight then only has to write 48 bone rotations a frame, and
## in-betweens come free. **It is also more faithful, not less** -- the snapping
## was a concession, and the original interpolates.
##
## ## The conversion, and what it costs
##
## The engine skins with `pos = SUM(A[k]*M3[k] + w[k]*T[k])`, where `A[k]` is the
## vertex position in bone k's local frame ALREADY MULTIPLIED BY ITS WEIGHT.
## Godot skins with `pos = SUM(w[k] * Global[k] * BindInverse[k] * v_rest)`.
##
## Those agree only if every influencing bone puts the vertex in the SAME place
## in some reference pose -- the bind pose. **This rig has no such pose exactly.**
## umk3_bindprobe.gd searched all 344 of Scorpion's frames and the best
## agreement left the bones 8.5 units apart, so the engine is not doing textbook
## linear blend skinning: each influence carries its own position and they do
## not have to be consistent.
##
## So the import is an APPROXIMATION, and the approximation is measured rather
## than hoped for. Picking the frame the bones agree in best and taking each
## vertex's rest position to be the blend the engine itself produces there:
##
##     bind = identity skeleton     mean 0.913, worst 15.109 units
##     bind = best frame (109)      mean 0.096, worst  2.236 units
##     bind = the stance (216)      mean 0.171, worst  3.733 units
##
## on a figure 140.1 units tall, over every 31st frame of the whole animation.
## A tenth of a unit is nothing; the 2.2 is one vertex at one extreme.
##
## **The engine-exact path is still there.** umk3_skin.gd skins on the CPU with
## no bind pose at all and reproduces the original bit for bit; this is the fast
## path, and the numbers above are the price.
##
## One convention flips on the way across: the engine is ROW-VECTOR (`v * M`)
## and Godot is column-vector (`M * v`), so a bone's Godot basis is the
## transpose of the engine's -- which is exactly `Basis(Quaternion(...))`,
## Godot's own conversion, rather than the transposed `_quat_m3` umk3_skin.gd
## needs. `PLAYER_TO_SCENE` is baked into every translation here, so the scene
## node carries rotation and mirror only.
##
## ## The frames are indexed by VISIT ORDER
##
## One animation frame is consumed per bone VISITED in the depth-first walk, not
## per bone index. Everything here goes through umk3_skin.gd's own walk so there
## is one place that knows it.
##
## ## No game data ships in the repository
##
## This writes into `res://assets/`, which the project's .gitignore excludes.
## The output is a local convenience built from the user's own copy of the game.
extends SceneTree

const UMK3Skin := preload("res://umk3/umk3_skin.gd")
const UMK3MeshSet := preload("res://umk3/umk3_meshset.gd")
const UMK3Textures := preload("res://umk3/umk3_textures.gd")

## `_PlayerSize / _SceneScale`, both literals in __DATA. A fighter and a stage
## are not drawn at the same scale.
const PLAYER_TO_SCENE := 0.762836

## **30 Hz, and that is a choice.** `next_anirate` is the engine's own animation
## clock and is not decompiled. The fight holds each animation frame for 2 game
## frames at 60, which is the same 30, so the two agree by construction.
const CLIP_HZ := 30.0

const OUT_ROOT := "res://assets/characters"

var res_dir := ""
var stem := ""
var skin = null

var bind_frame := 0
var _bind_pal: Array = []
## bone index -> its transform in the bind pose, Godot convention, scaled
var _bind_global: Array[Transform3D] = []
## bone index -> its transform relative to its parent, in the bind pose
var _bind_local: Array[Transform3D] = []
## visit slot -> bone index, and the reverse
var _order: PackedInt32Array = PackedInt32Array()
var _slot := {}
var _parent: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: ... --script umk3/umk3_import.gd -- <res dir> <NAME>")
		quit(2)
		return
	res_dir = args[0]
	stem = args[1]

	skin = UMK3Skin.new()
	if not skin.load_character(res_dir, stem):
		printerr(skin.error)
		quit(1)
		return
	print("%s: %d bones, %d verts, %d tris, %d frames"
		% [stem, skin.bones.size(), skin.block.num_matrices,
		   skin.block.num_verts, skin.num_frames])

	bind_frame = _find_bind()
	_bind_pal = skin.pose(bind_frame, bind_frame, 0.0)
	_walk()

	var mesh := _build_mesh()
	if mesh == null:
		quit(1)
		return

	var dir := OUT_ROOT.path_join(stem)
	DirAccess.make_dir_recursive_absolute(dir)
	var tex_path := _save_texture(dir)
	var scene := _build_scene(mesh, tex_path)

	var packed := PackedScene.new()
	packed.pack(scene)
	var out := dir.path_join("model.tscn")
	var err := ResourceSaver.save(packed, out)
	if err != OK:
		printerr("could not write %s (%d)" % [out, err])
		quit(1)
		return
	print("wrote " + out)
	quit(0)


## Which animation frame the bones agree in best. See the header: no frame makes
## them agree exactly, so this picks the least bad and the caller measures what
## that costs.
func _find_bind() -> int:
	var b = skin.block
	var sample: Array[int] = []
	var i := 0
	while i < b.num_matrices:
		sample.append(i)
		i += 17

	var best := 0
	var best_score := INF
	for f in skin.num_frames:
		var pal: Array = skin.pose(f, f, 0.0)
		var worst := 0.0
		for v in sample:
			var idx: int = b.indexes[v]
			var first := Vector3.ZERO
			var got := false
			for k in 4:
				var bone := (idx >> (8 * k)) & 0xFF
				if bone == 0xFF or bone >= pal.size():
					continue
				var w: float = b.weights[v * 4 + k]
				if w <= 0.0001:
					continue
				var e = pal[bone]
				var ao := v * 12 + k * 3
				var lp := Vector3(b.a[ao] / w, b.a[ao + 1] / w, b.a[ao + 2] / w)
				var p := Vector3.ZERO
				for c in 3:
					p[c] = lp.x * e.m[0 * 3 + c] + lp.y * e.m[1 * 3 + c] \
						+ lp.z * e.m[2 * 3 + c] + e.t[c]
				if not got:
					first = p
					got = true
				else:
					worst = maxf(worst, (p - first).length())
		if worst < best_score:
			best_score = worst
			best = f
	print("bind pose: frame %d, where the bones disagree by %.3f units"
		% [best, best_score])
	return best


## A palette entry as a Godot transform.
##
## The engine's 3x3 is ROW-VECTOR (`v * M`) and Godot's basis is column-vector,
## so this transposes. `Basis` takes its arguments as COLUMNS, so passing the
## engine's rows as columns is the transpose, written once.
static func _to_godot(e) -> Transform3D:
	var b := Basis(
		Vector3(e.m[0], e.m[1], e.m[2]),
		Vector3(e.m[3], e.m[4], e.m[5]),
		Vector3(e.m[6], e.m[7], e.m[8]))
	return Transform3D(b, e.t * PLAYER_TO_SCENE)


## Read one bone's rotation out of one animation frame, by VISIT SLOT.
func _quat_at(frame: int, slot: int) -> Quaternion:
	if slot >= skin.anim_bones:
		# ROBO1 and ROBO2 animate fewer bones than they have; those tail bones
		# genuinely carry no rotation track.
		return Quaternion.IDENTITY
	var o: int = skin.anim_header + frame * skin.frame_size + 16 + slot * 20
	var q := Quaternion(
		skin.anim.decode_float(o),
		skin.anim.decode_float(o + 4),
		skin.anim.decode_float(o + 8),
		skin.anim.decode_float(o + 12))
	if q.length_squared() <= 0.0:
		return Quaternion.IDENTITY
	return q.normalized()


func _root_pos(frame: int) -> Vector3:
	var base: int = skin.anim_header + frame * skin.frame_size
	return Vector3(
		skin.anim.decode_float(base + 4),
		skin.anim.decode_float(base + 8),
		skin.anim.decode_float(base + 12)) * PLAYER_TO_SCENE


## The depth-first walk, in the one order that matters, building the bind pose
## as Godot will compose it -- and checking that against the engine's own.
func _walk() -> void:
	var n: int = skin.bones.size()
	_bind_global.resize(n)
	_bind_local.resize(n)
	_parent.resize(n)
	for i in n:
		_parent[i] = -1

	var stack_bone := [skin.root]
	var stack_parent := [-1]
	while not stack_bone.is_empty():
		var bi: int = stack_bone.pop_back()
		var pa: int = stack_parent.pop_back()
		var slot := _order.size()
		_order.append(bi)
		_slot[bi] = slot
		_parent[bi] = pa

		# The root takes its translation from the animation; every other bone
		# takes it from the skeleton. Exactly as umk3_skin.gd's pose() does.
		var tr: Vector3 = _root_pos(bind_frame) if pa < 0 \
			else skin.bones[bi].offset * PLAYER_TO_SCENE
		var local := Transform3D(Basis(_quat_at(bind_frame, slot)), tr)
		_bind_local[bi] = local
		_bind_global[bi] = local if pa < 0 else _bind_global[pa] * local

		for j in range(skin.bones[bi].child.size() - 1, -1, -1):
			var c: int = skin.bones[bi].child[j]
			if c >= 0 and c < n:
				stack_bone.append(c)
				stack_parent.append(bi)

	# **The convention flip, checked rather than argued.** If transposing the
	# basis and composing the Godot way did not reproduce the engine's own
	# palette, every later number would be wrong in a way that still looks
	# plausible on screen.
	var worst := 0.0
	for bi in n:
		var want := _to_godot(_bind_pal[bi])
		var got: Transform3D = _bind_global[bi]
		worst = maxf(worst, (want.origin - got.origin).length())
		for c in 3:
			worst = maxf(worst, (want.basis[c] - got.basis[c]).length())
	print("convention check: Godot's chain matches the engine's to %.6f" % worst)


func _build_mesh() -> ArrayMesh:
	var b = skin.block
	var n: int = b.num_matrices

	# **The rest position is the engine's own output in the bind pose.** The
	# bones do not agree there, so there is no single "true" local position to
	# recover -- but the blend they produce is a real point, and it is the one
	# the game draws in that frame.
	var rest_pos := PackedVector3Array()
	var rest_nrm := PackedVector3Array()
	rest_pos.resize(n)
	rest_nrm.resize(n)

	var bad_weights := 0
	for i in n:
		var idx: int = b.indexes[i]
		var p := Vector3.ZERO
		var nr := Vector3.ZERO
		var wsum := 0.0
		for k in 4:
			var bone := (idx >> (8 * k)) & 0xFF
			if bone == 0xFF or bone >= _bind_pal.size():
				continue
			var w: float = b.weights[i * 4 + k]
			wsum += w
			var e = _bind_pal[bone]
			var ao := i * 12 + k * 3
			for c in 3:
				p[c] += (b.a[ao] * e.m[0 * 3 + c]
					+ b.a[ao + 1] * e.m[1 * 3 + c]
					+ b.a[ao + 2] * e.m[2 * 3 + c] + w * e.t[c]) * PLAYER_TO_SCENE
				nr[c] += b.b[ao] * e.m[0 * 3 + c] \
					+ b.b[ao + 1] * e.m[1 * 3 + c] \
					+ b.b[ao + 2] * e.m[2 * 3 + c]
		if absf(wsum - 1.0) > 0.01:
			bad_weights += 1
		rest_pos[i] = p
		rest_nrm[i] = nr.normalized() if nr.length() > 0.0 else Vector3.UP

	if bad_weights > 0:
		print("  %d of %d vertices have weights that do not sum to 1"
			% [bad_weights, n])

	# Expanded to a plain triangle list, because **the UVs are per CORNER**: a
	# shared position carries a different UV in each triangle it appears in.
	var m: int = b.num_verts
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var uv := PackedVector2Array()
	var bones := PackedInt32Array()
	var wts := PackedFloat32Array()
	v.resize(m * 3)
	nn.resize(m * 3)
	uv.resize(m * 3)
	bones.resize(m * 12)
	wts.resize(m * 12)

	for i in m * 3:
		var k: int = b.tri[i]
		if k >= n:
			k = 0
		v[i] = rest_pos[k]
		nn[i] = rest_nrm[k]
		uv[i] = b.uv[i]
		var idx: int = b.indexes[k]
		var tot := 0.0
		for j in 4:
			var bone := (idx >> (8 * j)) & 0xFF
			var w: float = b.weights[k * 4 + j]
			if bone == 0xFF or not _slot.has(bone):
				bone = skin.root
				w = 0.0
			# ARRAY_BONES indexes the SKELETON, which is in visit order, so the
			# engine's bone number is remapped here once rather than a bind
			# being reshuffled later.
			bones[i * 4 + j] = _slot[bone]
			wts[i * 4 + j] = w
			tot += w
		if tot > 0.0:
			for j in 4:
				wts[i * 4 + j] /= tot

	var arrays := []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = v
	arrays[ArrayMesh.ARRAY_NORMAL] = nn
	arrays[ArrayMesh.ARRAY_TEX_UV] = uv
	arrays[ArrayMesh.ARRAY_BONES] = bones
	arrays[ArrayMesh.ARRAY_WEIGHTS] = wts

	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.resource_name = stem
	return am


func _save_texture(dir: String) -> String:
	var ms := UMK3MeshSet.new()
	if not ms.load_file(res_dir.path_join(stem + ".meshset")) or ms.meshes.is_empty():
		return ""
	var tex = UMK3Textures.new(res_dir).get_texture(ms.meshes[0].texture)
	if tex == null:
		return ""
	var img := tex.get_image()
	var out := dir.path_join("body.png")
	img.save_png(out)
	print("wrote " + out)

	# **A PNG has to be imported before `load()` can see it**, and this script
	# runs headless with no editor. `PortableCompressedTexture2D` looked like
	# the way round that and is not: saved from a headless run it comes back
	# 362 bytes with a size of (0, 0), because the dummy renderer cannot
	# compress. So the flow is: write the PNG, run `godot --headless --import`,
	# run this again. The caller is told rather than left to wonder.
	if not ResourceLoader.exists(out):
		print("  (not imported yet -- run `godot --headless --import`, then "
			+ "this script again, and the texture will be attached)")
		return ""
	return out


## The LightVert shader.
##
## The engine lights every vertex on the CPU with two directional lights, a
## `pow()` falloff, NO AMBIENT AT ALL, and writes one grey as R=G=B. Doing that
## in a vertex shader keeps it exactly -- per vertex, after skinning, monochrome
## -- while the GPU does the skinning. umk3_light.gd has where the numbers come
## from and why light 0 ships with a power of zero.
func _shader() -> Shader:
	var s := Shader.new()
	s.code = """shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D body : source_color, filter_linear;
uniform vec3 dir0 = vec3(0.128, 0.872, 0.466);
uniform vec3 dir1 = vec3(0.0, -0.986, -0.164);
uniform float power0 = 0.0;
uniform float exp0 = 0.8;
uniform float power1 = 2.0;
uniform float exp1 = 3.5;
uniform float fill = 0.22;

varying float grey;

void vertex() {
	vec3 n = normalize(NORMAL);
	float l = 0.0;
	float d = max(-dot(n, dir0), 0.0);
	l += power0 * pow(d, exp0);
	d = max(-dot(n, dir1), 0.0);
	l += power1 * pow(d, exp1);
	l += fill;
	grey = min(l, 1.0);
}

void fragment() {
	vec4 c = texture(body, UV);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb * grey;
	ALPHA = 1.0;
}
"""
	return s


func _build_scene(mesh: ArrayMesh, tex_path: String) -> Node3D:
	var root := Node3D.new()
	root.name = stem
	root.set_meta("umk3_bind_frame", bind_frame)
	root.set_meta("umk3_source", stem)

	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	root.add_child(sk)
	sk.owner = root

	# Bones go in VISIT order, which is also the animation's frame order, so a
	# parent always exists before its child and slot N is frame slot N.
	for slot in _order.size():
		sk.add_bone("bone_%d" % _order[slot])
	for slot in _order.size():
		var bi: int = _order[slot]
		var pa: int = _parent[bi]
		if pa >= 0:
			sk.set_bone_parent(slot, _slot[pa])
		# The skeleton's REST is the bind pose, so an untouched model in the
		# editor stands in the pose its mesh was built for.
		sk.set_bone_rest(slot, _bind_local[bi])
		sk.set_bone_pose_position(slot, _bind_local[bi].origin)
		sk.set_bone_pose_rotation(slot, _bind_local[bi].basis.get_rotation_quaternion())

	var gskin := Skin.new()
	for slot in _order.size():
		gskin.add_bind(slot, _bind_global[_order[slot]].affine_inverse())

	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mesh
	mi.skin = gskin
	var mat := ShaderMaterial.new()
	mat.shader = _shader()
	if tex_path != "":
		mat.set_shader_parameter("body", load(tex_path))
	mesh.surface_set_material(0, mat)
	sk.add_child(mi)
	mi.owner = root

	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	ap.owner = root
	var lib := _animations(sk)
	ap.add_animation_library("", lib)
	print("  %d clips" % lib.get_animation_list().size())
	return root


## One Animation per named clip, from the character's own frame list.
##
## `res/framelists/<name>frames.txt` names every frame, one per line, and a clip
## is the run that shares a prefix: SCBLOCK1, SCBLOCK2, SCBLOCK3 is SCBLOCK.
## That is where the C project's clip table came from, transcribed by hand; this
## reads the same file and gets every clip without transcribing any of them.
func _animations(sk: Skeleton3D) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	var names := _frame_names()

	var clips := {}
	var order: Array[String] = []
	var marked := 0
	for i in names.size():
		var base: String = names[i]
		# **Some frames carry an event marker**, written after a double slash:
		# `BABYSCORP//doFatal`, `JAX_SQUASH_SCORPION//doFatal`. That is the
		# frame list telling us which frame fires the fatality, and it is worth
		# knowing -- ten of Scorpion's do. Only the name is taken here; wiring
		# the event up is fight logic and not import.
		var cut := base.find("//")
		if cut >= 0:
			base = base.substr(0, cut)
			marked += 1
		while base.length() > 0 and base[base.length() - 1] in "0123456789":
			base = base.substr(0, base.length() - 1)
		# Godot rejects an animation name holding / : , or [.
		for bad in ["/", ":", ",", "[", "]"]:
			base = base.replace(bad, "_")
		if base == "":
			base = "FRAME"
		if not clips.has(base):
			clips[base] = []
			order.append(base)
		clips[base].append(i)

	for base in order:
		var frames: Array = clips[base]
		if not frames.is_empty():
			lib.add_animation(base, _clip(sk, frames))
	if marked > 0:
		print("  %d frames carry a // event marker" % marked)
	return lib


func _frame_names() -> PackedStringArray:
	# The list is named after the character, lower-cased, without the variant:
	# SCORPION_STANDARD -> scorpionframes.txt.
	var who := stem.get_slice("_", 0).to_lower()
	var path := res_dir.path_join("framelists").path_join(who + "frames.txt")
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("  no frame list at %s -- one clip called ALL" % path)
		var all := PackedStringArray()
		for i in skin.num_frames:
			all.append("ALL%d" % i)
		return all
	var out := PackedStringArray()
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line != "":
			out.append(line)
	f.close()
	return out


func _clip(sk: Skeleton3D, frames: Array) -> Animation:
	var anim := Animation.new()
	anim.length = maxf(float(frames.size()) / CLIP_HZ, 1.0 / CLIP_HZ)
	anim.loop_mode = Animation.LOOP_NONE

	var rot := PackedInt32Array()
	for slot in _order.size():
		var t := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(t, NodePath("Skeleton3D:" + sk.get_bone_name(slot)))
		rot.append(t)
	# A position track for the ROOT only: every other bone's translation is the
	# skeleton's own offset and never changes.
	var pos_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pos_track, NodePath("Skeleton3D:" + sk.get_bone_name(0)))

	for i in frames.size():
		var fr: int = frames[i]
		if fr >= skin.num_frames:
			continue
		var at := float(i) / CLIP_HZ
		anim.position_track_insert_key(pos_track, at, _root_pos(fr))
		for slot in _order.size():
			anim.rotation_track_insert_key(rot[slot], at, _quat_at(fr, slot))
	return anim
