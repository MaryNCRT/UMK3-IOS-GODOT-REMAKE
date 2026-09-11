## What is actually in GYMIST1: the alpha stream, the texture, the size.
##
##     godot --headless --path <project> --script umk3/umk3_fxprobe.gd -- <res dir>
##
## The port drew the mist as a wall across the whole screen where the C demo
## draws faint bands between the gravestones. Three things could do that -- the
## per-frame alpha, the texture's own alpha channel, or the size of the quad --
## and this prints all three rather than guessing which.
extends SceneTree

const _MeshSet := preload("res://umk3/umk3_meshset.gd")
const _Scene := preload("res://umk3/umk3_scene.gd")
const _Events := preload("res://umk3/umk3_events.gd")
const _Textures := preload("res://umk3/umk3_textures.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: ... -- <res dir>")
		quit(2)
		return
	var res: String = args[0]

	var ev := _Events.new()
	if ev.load_file(res.path_join("GRAVEYARD_LEVEL_SCENE.events")):
		print("events: %d tracks" % ev.tracks.size())
		for t in ev.tracks:
			print("   %-10s origin %s  basis x%s y%s z%s"
				% [t.name, t.origin, t.basis.x, t.basis.y, t.basis.z])

	var ms := _MeshSet.new()
	if ms.load_file(res.path_join("GYMIST1.meshset")):
		for m in ms.meshes:
			var lo := Vector3(INF, INF, INF)
			var hi := -lo
			for p in m.positions:
				lo = lo.min(p)
				hi = hi.max(p)
			print("mesh %-14s %d verts  texture %-18s  size %s"
				% [m.name, m.positions.size(), m.texture, hi - lo])

	var sc := _Scene.new()
	if sc.load_file(res.path_join("GYMIST1.scene")):
		print("scene: %d nodes, %d frames" % [sc.nodes.size(), sc.num_frames])
		for i in sc.nodes.size():
			var nd = sc.nodes[i]
			var mn := INF
			var mx := -INF
			for a in nd.alpha:
				mn = minf(mn, a)
				mx = maxf(mx, a)
			print("   node %-14s alpha %.3f .. %.3f   first ten: %s"
				% [nd.name, mn, mx,
				   str(Array(nd.alpha).slice(0, 10)).substr(0, 80)])
			var p0 = sc.placement_for(i, 0)
			if p0:
				print("      frame 0 scale %s  origin %s" % [p0.scale, p0.origin])

	var tex = _Textures.new(res).get_texture("ALPHA_GYMIST1.???")
	if tex:
		var img := tex.get_image()
		var lo := 255
		var hi := 0
		var sum := 0
		var n := 0
		for y in range(0, img.get_height(), 4):
			for x in range(0, img.get_width(), 4):
				var a := int(img.get_pixel(x, y).a * 255.0)
				lo = mini(lo, a)
				hi = maxi(hi, a)
				sum += a
				n += 1
		print("texture %dx%d  alpha %d..%d, mean %.1f"
			% [img.get_width(), img.get_height(), lo, hi, float(sum) / maxf(n, 1)])
	else:
		print("texture ALPHA_GYMIST1: NOT FOUND")
	quit(0)
