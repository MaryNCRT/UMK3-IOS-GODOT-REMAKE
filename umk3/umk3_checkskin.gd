## Headless check: read every character's `.bones` / `.skin` / `.skinanim` and
## report. The Godot side of what `tools/skin.py --check` does in the C project.
##
##     godot --headless --path <project> --script umk3/umk3_checkskin.gd -- <res dir>
##
## An exact landing on EOF is the whole of the evidence that the strides are
## right, so a file that parses is a file whose layout is confirmed. This also
## times one pose+skin, because GDScript cost decides whether the fighter can be
## rebuilt every frame or has to be cached.
extends SceneTree

const UMK3Skin := preload("res://umk3/umk3_skin.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: ... --script umk3/umk3_checkskin.gd -- <path to UMK3.app/res>")
		quit(2)
		return
	var res_dir: String = args[0]

	# Every character the folder has, found by its .skin.
	var stems: Array[String] = []
	var d := DirAccess.open(res_dir)
	if d == null:
		printerr("cannot open " + res_dir)
		quit(2)
		return
	d.list_dir_begin()
	while true:
		var f := d.get_next()
		if f == "":
			break
		if f.ends_with(".skin"):
			stems.append(f.substr(0, f.length() - 5))
	d.list_dir_end()
	stems.sort()

	var ok := 0
	var bad := 0
	for stem in stems:
		var sk := UMK3Skin.new()
		if sk.load_character(res_dir, stem):
			ok += 1
			print("  OK   %-22s %2d bones (root %d)  %4d verts  %4d tris  %4d frames  %d anim bones"
				% [stem, sk.bones.size(), sk.root, sk.block.num_matrices,
				   sk.block.num_verts, sk.num_frames, sk.anim_bones])
		else:
			bad += 1
			print("  FAIL %-22s %s" % [stem, sk.error])

	print("\n%d of %d characters read" % [ok, ok + bad])

	# How expensive is one frame, really? Measured, not assumed.
	var s := UMK3Skin.new()
	if s.load_character(res_dir, "SCORPION_STANDARD"):
		var t0 := Time.get_ticks_usec()
		var n := 20
		for i in n:
			var pal := s.pose(216 + (i % 9), 216 + ((i + 1) % 9), 0.5)
			s.skin(pal)
		var us := (Time.get_ticks_usec() - t0) / n
		print("SCORPION_STANDARD: pose+skin = %d us  (%.1f ms, %d verts)"
			% [us, us / 1000.0, s.block.num_matrices])

	quit(0 if bad == 0 else 1)
