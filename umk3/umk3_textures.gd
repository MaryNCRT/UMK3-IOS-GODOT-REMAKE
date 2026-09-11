## Resolves a mesh's texture name to a Godot texture, with a disk cache.
##
## A `.meshset` names its texture as `COBBLES.???` -- the literal `???` is an
## exporter placeholder and the engine resolves the real extension itself. The
## search order is ported from `lime_texture_load` in `runtime/lime/pvr.c`:
## `Textures/` first, then the root, `.pvr` then `.PVR`, then PNG.
##
## ## Why the cache exists
##
## PVRTC decoding is per-pixel and GDScript is slow at it. A 512x512 texture is
## 262,144 pixels of bilinear endpoint blending, and a stage wants twenty of
## them. Decoding once and keeping the PNG makes the second run instant.
##
## The cache lives in `user://umk3_texcache`, outside the project, and the key
## carries the source file's size and modification time -- so pointing at a
## different `res` folder, or replacing one, invalidates it without a flag.
class_name UMK3Textures
extends RefCounted

const _Pvr := preload("res://umk3/umk3_pvr.gd")

const CACHE_DIR := "user://umk3_texcache"

## name -> ImageTexture, for the life of this object.
var _memo := {}
var res_dir := ""

var decoded := 0            ## how many came from PVRTC this session
var from_cache := 0
var from_png := 0
var missing: Array[String] = []


func _init(dir: String) -> void:
	res_dir = dir
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)


static func _stem(mesh_texture: String) -> String:
	var s := mesh_texture
	var dot := s.rfind(".")
	if dot >= 0:
		s = s.substr(0, dot)
	return s


## Every place the engine looks, in the engine's own order.
func _candidates(stem: String) -> Array[String]:
	var out: Array[String] = []
	for ext in [".pvr", ".PVR", ".PNG", ".png"]:
		out.append(res_dir.path_join("Textures").path_join(stem + ext))
		out.append(res_dir.path_join(stem + ext))
	return out


func _cache_key(path: String) -> String:
	var t := FileAccess.get_modified_time(path)
	var sz := 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		sz = f.get_length()
		f.close()
	return "%s_%d_%d.png" % [path.get_file().get_basename(), sz, t]


## Returns an ImageTexture, or null when the texture genuinely is not there.
## `NOTEXTURE` is a real name in the files and is not an error.
func get_texture(mesh_texture: String) -> ImageTexture:
	if mesh_texture == "" or mesh_texture.begins_with("NOTEXTURE"):
		return null
	if _memo.has(mesh_texture):
		return _memo[mesh_texture]

	var stem := _stem(mesh_texture)
	var src := ""
	for c in _candidates(stem):
		if FileAccess.file_exists(c):
			src = c
			break

	if src == "":
		if not missing.has(stem):
			missing.append(stem)
		_memo[mesh_texture] = null
		return null

	var img: Image = null

	# PNG needs no decoding and no cache -- Godot reads it directly.
	if src.to_lower().ends_with(".png"):
		img = Image.new()
		var f := FileAccess.open(src, FileAccess.READ)
		if f:
			var err := img.load_png_from_buffer(f.get_buffer(f.get_length()))
			f.close()
			if err != OK:
				img = null
		if img:
			from_png += 1
	else:
		var cache := CACHE_DIR.path_join(_cache_key(src))
		if FileAccess.file_exists(cache):
			img = Image.new()
			var f := FileAccess.open(cache, FileAccess.READ)
			if f:
				if img.load_png_from_buffer(f.get_buffer(f.get_length())) != OK:
					img = null
				f.close()
			if img:
				from_cache += 1
		if img == null:
			img = _Pvr.load_pvr(src)
			if img:
				decoded += 1
				img.save_png(cache)

	if img == null:
		if not missing.has(stem):
			missing.append(stem)
		_memo[mesh_texture] = null
		return null

	var tex := ImageTexture.create_from_image(img)
	_memo[mesh_texture] = tex
	return tex


func report() -> String:
	return "textures: %d decoded, %d cached, %d png, %d missing%s" % [
		decoded, from_cache, from_png, missing.size(),
		("  (" + ", ".join(missing.slice(0, 6)) + ")") if missing.size() > 0 else ""]
