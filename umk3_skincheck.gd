## The fast skinner against the readable one.
##
##     godot --headless --path <project> --script umk3/umk3_skincheck.gd -- \
##           <res dir> [NAME]
##
## `skin()` was rewritten to run 2.6 times faster -- flattening the palette into
## a float array, writing x/y/z out instead of looping, inlining the light and
## dropping the term whose power is a literal zero. Every one of those is a
## chance to change the answer while the model still looks like a man.
##
## So this runs both over real poses and reports the largest disagreement in
## position and in the lit grey. It is the same discipline the C project uses
## against the recompiled original: a faster version that is not the same
## version is not faster, it is different.
extends SceneTree

const UMK3Skin := preload("res://umk3/umk3_skin.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: ... -- <res dir> [NAME]")
		quit(2)
		return
	var res_dir: String = args[0]
	var stems: Array[String] = []
	if args.size() > 1:
		stems.append(args[1])
	else:
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

	var worst_pos := 0.0
	var worst_grey := 0.0
	var checked := 0
	var failed := 0

	for stem in stems:
		var skin = UMK3Skin.new()
		if not skin.load_character(res_dir, stem):
			print("  skip %-22s %s" % [stem, skin.error])
			failed += 1
			continue

		var wp := 0.0
		var wg := 0.0
		# Every 37th frame, and the halfway blend between it and the next: the
		# in-betweens are the whole reason interpolation is on.
		var f := 0
		while f < skin.num_frames:
			var pal: Array = skin.pose(f, mini(f + 1, skin.num_frames - 1), 0.5)
			var fast: Array = skin.skin(pal)
			var slow: Array = skin.skin_reference(pal)
			var pa: PackedVector3Array = fast[0]
			var pb: PackedVector3Array = slow[0]
			var ca: PackedColorArray = fast[1]
			var cb: PackedColorArray = slow[1]
			for i in pa.size():
				wp = maxf(wp, (pa[i] - pb[i]).length())
				wg = maxf(wg, absf(ca[i].r - cb[i].r))
			f += 37
		checked += 1
		worst_pos = maxf(worst_pos, wp)
		worst_grey = maxf(worst_grey, wg)
		print("  %-22s position %.9f   grey %.9f" % [stem, wp, wg])

	print("\n%d characters checked, %d unreadable" % [checked, failed])
	print("worst position difference %.9f units, worst grey %.9f"
		% [worst_pos, worst_grey])
	# Float arithmetic reassociated is not bit-identical and never will be; the
	# bar is that nothing moves by a distance that could be seen on a model 140
	# units tall.
	if worst_pos > 0.001 or worst_grey > 0.001:
		printerr("TOO FAR APART -- the fast path is not the same computation")
		quit(1)
		return
	quit(0)
