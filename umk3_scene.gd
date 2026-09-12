## .scene reader -- the scene graph that says WHERE each stage object goes.
##
## Ported from `runtime/lime/scene.c`, derived from `LIME_LoadScene`
## (armv7 0x0005f0ac). The spec is docs/SCENE-FORMAT.md.
##
## ## Why this file matters more than it looks
##
## A stage `.meshset` holds its objects in LOCAL space. Drawing them all at the
## origin piles a graveyard into one heap -- an earlier demo in the C project
## did exactly that. The `.scene` is what puts them where they belong.
##
## ## Every stride came from the loader, not from a fitted formula
##
## That distinction is the whole point of the format doc: an earlier attempt
## produced a formula that matched 71 of 92 single-object files, a near-miss
## that looked like a solution. The strides below are the ones the disassembly
## adds to its cursor.
##
##   header    two int32: numObjects, count2       cursor at +8
##   object    64 bytes, memcpy'd verbatim
##   tracks    count2 records of 12 bytes, PER OBJECT
##   count3    one int32
##   tail      count3 records of 40 bytes -- the placements
##
## A file whose tail does not end exactly at EOF is rejected rather than
## guessed at. Two shipped files fail that check and they are stub exports.
class_name UMK3Scene
extends RefCounted

## Needed for `_cstr`; preloaded so this file also parses before the editor has
## built its class index.
const _MeshSet := preload("res://umk3/umk3_meshset.gd")

const HIDDEN := 0xFFFF

## One placement: a quaternion, a scale and a translation.
class Placement extends RefCounted:
	var basis_q := Quaternion.IDENTITY
	var scale := Vector3.ONE
	var origin := Vector3.ZERO

	func to_transform() -> Transform3D:
		return Transform3D(Basis(basis_q).scaled(scale), origin)


class Node3DEntry extends RefCounted:
	var name: String
	## One entry per frame; HIDDEN means the object is not drawn that frame.
	var stream: PackedInt32Array
	## Parallel to the visible keys: which placement each one uses.
	var palette_index: PackedInt32Array
	var alpha: PackedFloat32Array


var placements: Array[Placement] = []
var nodes: Array[Node3DEntry] = []
var num_frames := 0
var error := ""

## LIME_RenderScene hands anything under this to the additive transparent list.
## Established by bisection against the recompiled original: 0.9700 behaves as
## opaque and 0.9699 does not.
const OPAQUE_ALPHA := 0.97

## The visibility test in the loader is `ble -> skip`, so a track value has to
## be strictly greater than zero to produce a key.
const VISIBLE_THRESHOLD := 0.0


func load_file(path: String) -> bool:
	placements.clear()
	nodes.clear()
	error = ""

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		error = "cannot open %s" % path
		return false
	var b := f.get_buffer(f.get_length())
	f.close()

	if b.size() < 8:
		error = "%s is too short" % path
		return false

	var num_objects := b.decode_s32(0)
	var count2 := b.decode_s32(4)
	if num_objects < 0 or count2 <= 0:
		error = "%s has a nonsense header" % path
		return false

	var obj_stride := 64 + count2 * 12
	var tail_off := 8 + num_objects * obj_stride
	if tail_off + 4 > b.size():
		error = "%s: the tail is past the end" % path
		return false

	var count3 := b.decode_s32(tail_off)
	if count3 < 0 or tail_off + 4 + count3 * 40 != b.size():
		# ROBO1/ROBO2 are stub exports. Refuse rather than read garbage.
		error = "%s: the tail does not land on EOF" % path
		return false

	# ---------------------------------------------------------- placements
	#
	# The four quaternion floats are multiplied by 32767 and narrowed in the
	# original, then divided back out when a matrix is built. Doing both here
	# would only reproduce its rounding; Godot wants a float quaternion, so the
	# round trip is skipped and the file's floats are used directly.
	#
	# The C port keeps the narrowing because it is matching the original bit
	# for bit. This one is not, and says so.
	for i in count3:
		var r := tail_off + 4 + i * 40
		var p := Placement.new()
		p.basis_q = Quaternion(
			b.decode_float(r), b.decode_float(r + 4),
			b.decode_float(r + 8), b.decode_float(r + 12)).normalized()
		p.scale = Vector3(b.decode_float(r + 0x10),
						  b.decode_float(r + 0x14),
						  b.decode_float(r + 0x18))
		p.origin = Vector3(b.decode_float(r + 0x1c),
						   b.decode_float(r + 0x20),
						   b.decode_float(r + 0x24))
		placements.append(p)

	num_frames = count2

	# -------------------------------------------------------- node streams
	for i in num_objects:
		var obj := 8 + i * obj_stride
		var nd := Node3DEntry.new()
		nd.name = _MeshSet._cstr(b, obj, 64)
		nd.stream.resize(count2)
		nd.palette_index.resize(count2)
		nd.alpha.resize(count2)

		for k in count2:
			var trk := obj + 64 + k * 12
			var value := b.decode_float(trk)
			nd.stream[k] = HIDDEN
			nd.alpha[k] = value
			nd.palette_index[k] = -1
			if value > VISIBLE_THRESHOLD:
				nd.stream[k] = 1
				nd.palette_index[k] = b.decode_u16(trk + 8)
		nodes.append(nd)

	return true


## The placement an object uses on a given frame, or null when it is hidden.
func placement_for(node_index: int, frame: int) -> Placement:
	if node_index < 0 or node_index >= nodes.size():
		return null
	var nd := nodes[node_index]
	if frame < 0 or frame >= nd.stream.size():
		return null
	if nd.stream[frame] == HIDDEN:
		return null
	var pi := nd.palette_index[frame]
	if pi < 0 or pi >= placements.size():
		return null
	return placements[pi]
