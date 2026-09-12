## .meshset reader -- the UMK3 iOS (LIME engine) static mesh container.
##
## Ported from `runtime/lime/meshset.c` in the decompilation project, which was
## derived from the disassembly of `_LIME_LoadMeshSet` (armv7 0x0005ea34) and
## validated against 604 of the 605 shipped files with the walk landing on the
## exact final offset. The spec is docs/MESHSET-FORMAT.md there.
##
## ## No game data ships with this project
##
## Every path this reads is given by the caller and points into the user's own
## extracted `UMK3.app/res`. That is the same rule the C port follows and it is
## not negotiable: the format knowledge is ours, the data is EA's.
##
## ## Three variants, and nothing in the file says which
##
## There is no magic number and no version field. A file is parsed under each
## layout in turn and the one whose walk lands exactly on the end -- or on the
## text block the exporter left behind -- is the right one.
##
##   A  140-byte header, indexed, 26-byte vertices, int16 positions / 32767
##   B  136-byte header, indexed, 20-byte vertices, float positions
##   C  136-byte header, NOT indexed, 20-byte vertices, numFaces*3 of them
##
## **Variant C's `numVerts` header field describes no buffer in the file.** It
## is the count before duplication; advancing the cursor by it corrupts the
## read. The C loader carries the same warning.
class_name UMK3MeshSet
extends RefCounted

const HEADER_A := 140
const HEADER_B := 136
const VERT_A := 26
const VERT_B := 20

## The first line of the C source fragment some exports leave after the data.
const TAIL_MARK := "//====="

## One mesh record. Named MeshRecord and not Mesh because GDScript refuses an
## inner class that hides a native one, and `Mesh` is Godot's own.
class MeshRecord extends RefCounted:
	var name: String
	var texture: String
	var num_verts: int
	var num_faces: int
	var radius: float
	var variant: String
	var indices: PackedInt32Array      ## num_faces * 3, empty for variant C
	var positions: PackedVector3Array
	var uvs: PackedVector2Array
	## **Variant A only, and the engine throws them away.** The 26-byte vertex
	## ends with three floats the iOS loader skips -- it advances 26 in the
	## source and 16 in the destination, copying only the first 14 bytes. They
	## are the vertex normal, and they are read here because the engine's own
	## lighting model needs them and the baked `.lighting` files are not
	## decoded. Empty for variants B and C, whose 20-byte vertex has no room.
	var normals: PackedVector3Array


var meshes: Array[MeshRecord] = []
var variant := ""
var error := ""


static func _cstr(b: PackedByteArray, at: int, n: int) -> String:
	var e := at
	var stop := at + n
	while e < stop and b[e] != 0:
		e += 1
	return b.slice(at, e).get_string_from_ascii()


## One parse attempt under a fixed layout. Returns the final offset, or -1.
func _parse_as(b: PackedByteArray, v: String, out: Array[MeshRecord]) -> int:
	var size := b.size()
	if size < 4:
		return -1

	var hsize := HEADER_A if v == "A" else HEADER_B
	var vsize := VERT_A if v == "A" else VERT_B
	var indexed := v != "C"

	var n := b.decode_s32(0)
	if n < 0 or n > 4096:
		return -1

	var off := 4
	for i in n:
		if off + hsize > size:
			return -1

		var m := MeshRecord.new()
		m.name = _cstr(b, off, 64)
		m.texture = _cstr(b, off + 64, 64)
		m.num_verts = b.decode_s32(off + 128)
		m.num_faces = b.decode_s32(off + 132)
		m.radius = b.decode_float(off + 136) if v == "A" else 0.0
		m.variant = v

		if m.num_verts < 0 or m.num_faces < 0:
			return -1
		if m.num_verts > 1000000 or m.num_faces > 1000000:
			return -1

		off += hsize

		if indexed:
			var ibytes := m.num_faces * 6
			if off + ibytes > size:
				return -1
			m.indices.resize(m.num_faces * 3)
			for k in m.num_faces * 3:
				m.indices[k] = b.decode_u16(off + k * 2)
			off += ibytes

		# Variant C stores numFaces*3 already-expanded vertices; its numVerts
		# field is the count BEFORE duplication and describes nothing on disk.
		var vcount := m.num_faces * 3 if v == "C" else m.num_verts
		var vbytes := vcount * vsize
		if off + vbytes > size:
			return -1

		var pos_div := m.radius if m.radius != 0.0 else 1.0

		m.positions.resize(vcount)
		m.uvs.resize(vcount)
		if v == "A":
			m.normals.resize(vcount)
		for k in vcount:
			var p := off + k * vsize
			if v == "A":
				# int16 x,y,z then two UNALIGNED floats at +6 and +10. The
				# trailing 12 bytes are almost certainly the normal and the
				# engine discards them -- lighting comes from .lighting.
				#
				# **Divided by the mesh's boundsRadius, NOT by 32767.**
				# docs/MESHSET-FORMAT.md says `int16 / 32767`, and that is what
				# this file did first: every mesh came out two units across,
				# correctly placed and far too small to see. The working C
				# loader in runtime/lime/meshset.c divides by `radius` instead,
				# and it is the one that renders. A zero radius falls back to
				# 1 rather than producing infinities, as it does there.
				m.positions[k] = Vector3(
					float(b.decode_s16(p)) / pos_div,
					float(b.decode_s16(p + 2)) / pos_div,
					float(b.decode_s16(p + 4)) / pos_div)
				m.uvs[k] = Vector2(b.decode_float(p + 6), b.decode_float(p + 10))
				m.normals[k] = Vector3(
					b.decode_float(p + 14),
					b.decode_float(p + 18),
					b.decode_float(p + 22))
			else:
				m.positions[k] = Vector3(
					b.decode_float(p),
					b.decode_float(p + 4),
					b.decode_float(p + 8))
				m.uvs[k] = Vector2(b.decode_float(p + 12), b.decode_float(p + 16))
		off += vbytes

		out.append(m)

	return off


func _landed(b: PackedByteArray, off: int) -> bool:
	if off == b.size():
		return true
	var n := TAIL_MARK.length()
	if off < 0 or off + n > b.size():
		return false
	return b.slice(off, off + n).get_string_from_ascii() == TAIL_MARK


## Read a .meshset from an absolute path on disk. Returns true on success; on
## failure `error` says what happened.
func load_file(path: String) -> bool:
	meshes.clear()
	variant = ""
	error = ""

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		error = "cannot open %s" % path
		return false
	var b := f.get_buffer(f.get_length())
	f.close()

	if b.size() == 0:
		error = "%s is empty" % path        # LAVALEVEL0.meshset really is
		return false

	for v in ["A", "B", "C"]:
		var cand: Array[MeshRecord] = []
		var off := _parse_as(b, v, cand)
		if off >= 0 and _landed(b, off):
			meshes = cand
			variant = v
			return true

	error = "%s matches no known variant" % path
	return false


func total_triangles() -> int:
	var t := 0
	for m in meshes:
		t += m.num_faces
	return t
