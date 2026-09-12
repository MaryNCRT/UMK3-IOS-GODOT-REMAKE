## Decode named textures to PNG so they can be looked at.
##
##   godot --headless --path . --script umk3/umk3_dumptex.gd -- <res> <outdir> NAME...
extends SceneTree

const _Tex := preload("res://umk3/umk3_textures.gd")

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		printerr("need <res> <outdir> NAME...")
		quit(2); return
	var res_dir: String = args[0]
	var outdir: String = args[1]
	DirAccess.make_dir_recursive_absolute(outdir)
	var tex := _Tex.new(res_dir)
	for i in range(2, args.size()):
		var name: String = args[i]
		var t: ImageTexture = tex.get_texture(name + ".???")
		if t == null:
			print("  MISSING  " + name)
			continue
		var img := t.get_image()
		var p := outdir.path_join(name + ".png")
		img.save_png(p)
		print("  %-28s %4dx%-4d alpha=%s" % [name, img.get_width(),
			img.get_height(), img.detect_alpha() != Image.ALPHA_NONE])
	print(tex.report())
	quit(0)
