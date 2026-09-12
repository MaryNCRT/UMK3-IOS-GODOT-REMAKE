## Where does an interpolated pose actually spend its time?
##
##     godot --headless --path <project> --script umk3/umk3_posebench.gd -- \
##           <res dir> SCORPION_STANDARD
##
## Interpolating means rebuilding the character every frame, and the first
## attempt at that ran at 18 fps with 14 ms a frame in posing. Before making
## anything faster: which of the three stages is the 14 ms?
##
##     pose()   48 bones, a quaternion blend and a matrix chain each
##     skin()   1,278 vertices, four bone influences, plus the light per vertex
##     build    expanding to 7,509 corners and handing Godot an ArrayMesh
##
## Optimising the wrong one is how an afternoon disappears -- this session has
## already spent three runs on a GDScript parser that turned out to be fine.
extends SceneTree

const UMK3Skin := preload("res://umk3/umk3_skin.gd")
const PLAYER_TO_SCENE := 0.762836

const N := 30


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: ... -- <res dir> <NAME>")
		quit(2)
		return
	var skin = UMK3Skin.new()
	if not skin.load_character(args[0], args[1]):
		printerr(skin.error)
		quit(1)
		return

	var b = skin.block
	print("%s: %d bones, %d skinned verts, %d triangles"
		% [args[1], skin.bones.size(), b.num_matrices, b.num_verts])

	# --- pose
	var t0 := Time.get_ticks_usec()
	var pal: Array = []
	for i in N:
		pal = skin.pose(216 + (i % 9), 216 + ((i + 1) % 9), 0.5)
	var t_pose := float(Time.get_ticks_usec() - t0) / N

	# --- skin
	t0 = Time.get_ticks_usec()
	var r: Array = []
	for i in N:
		r = skin.skin(pal)
	var t_skin := float(Time.get_ticks_usec() - t0) / N

	# --- expand and hand to Godot
	t0 = Time.get_ticks_usec()
	for i in N:
		_build(b, r[0], r[1])
	var t_build := float(Time.get_ticks_usec() - t0) / N

	# --- the same expansion without the ArrayMesh, to separate the arithmetic
	#     from what Godot does with the result
	t0 = Time.get_ticks_usec()
	for i in N:
		_expand_only(b, r[0], r[1])
	var t_expand := float(Time.get_ticks_usec() - t0) / N

	print("pose    %7.0f us" % t_pose)
	print("skin    %7.0f us" % t_skin)
	print("expand  %7.0f us   (of which ArrayMesh %.0f us)"
		% [t_build, t_build - t_expand])
	print("total   %7.0f us a fighter, %.1f ms for two"
		% [t_pose + t_skin + t_build, (t_pose + t_skin + t_build) * 2.0 / 1000.0])
	quit(0)


func _build(b, pos: PackedVector3Array, col: PackedColorArray) -> ArrayMesh:
	var arrays := _expand_only(b, pos, col)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


func _expand_only(b, pos: PackedVector3Array, col: PackedColorArray) -> Array:
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
	return arrays
