## Headless check: parse every stage the C project's selector lists and report.
##
##     godot --headless --path <project> --script umk3/umk3_check.gd -- <res dir>
##
## This is the Godot side of what `tools/meshset.py --check` does in the C
## project: it proves the reader against real files rather than against one.
extends SceneTree

## **preload, not class_name.** A `class_name` is only visible once the editor
## has indexed the project, and `--script` on a fresh checkout has no index --
## which is exactly when this check is most useful. preload resolves at parse
## time and needs nothing.
const UMK3MeshSet := preload("res://umk3/umk3_meshset.gd")
const UMK3Scene := preload("res://umk3/umk3_scene.gd")

const STAGES := [
	"GRAVEYARD_LEVEL_SCENE", "BALCONY_LEVEL_SCENE", "BELLTOWER_LEVEL_SCENE",
	"BRIDGE_LEVEL_SCENE", "CAVE_LEVEL_SCENE", "JADESDESERT_LEVEL_SCENE",
	"LAIR_LEVEL_SCENE", "NOOBSDORFEN_LEVEL_SCENE", "PIT_LEVEL_SCENE",
	"ROOFTOP_LEVEL_SCENE", "SCISLACBUSOREZ_LEVEL_SCENE",
]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: ... --script umk3/umk3_check.gd -- <path to UMK3.app/res>")
		quit(2)
		return
	var res_dir: String = args[0]

	var ok := 0
	var bad := 0
	for stem in STAGES:
		var ms := UMK3MeshSet.new()
		var sc := UMK3Scene.new()
		if not ms.load_file(res_dir.path_join(stem + ".meshset")):
			printerr("  MESHSET FAIL  %s: %s" % [stem, ms.error])
			bad += 1
			continue
		var scene_ok := sc.load_file(res_dir.path_join(stem + ".scene"))
		print("  %-28s variant %s  %3d meshes  %6d tris  scene %s"
			% [stem, ms.variant, ms.meshes.size(), ms.total_triangles(),
			   ("%d obj / %d frames / %d placements"
					% [sc.nodes.size(), sc.num_frames, sc.placements.size()])
				if scene_ok else ("no (" + sc.error + ")")])
		ok += 1
	print("")
	print("  %d parsed, %d failed" % [ok, bad])
	quit(1 if bad > 0 else 0)
