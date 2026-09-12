## `.events` -- where a stage's effects go.
##
## Ported from `runtime/lime/events.c`, whose strides come from `LIME_LoadEvents`
## (0x000a477c) rather than from a walk over the file:
##
##     int32   numTracks
##     track   268 bytes: name at +0x000, slot at +0x0c8, numEntries at +0x108
##     entry    56 bytes, and the FIRST one carries the transform, after its
##              two leading int32s: nine int32 of 3x3 then three of translation
##
## All of it 12.12 fixed point -- 4096 is 1.0. Graveyard's identity rows read
## 4096 and 4095, which is the exporter rounding and not two different scales.
##
## ## Why this file rather than the scene's own markers
##
## Graveyard's seven tracks are all named `gymist1`, and their translations are
## byte for byte the positions of the seven `EVENT_gymist*` nodes in the stage's
## `.scene`. Two independent files agreeing to the last digit is what makes this
## a reading and not a guess.
##
## But `.events` carries more than the markers do: **a 3x3 that is not the
## identity.** The Y scales run 0.93, 0.69, 0.64, 0.55 and 0.36, and two tracks
## have X and Y both negative -- which is not a mirror, the determinant stays
## positive at 0.693, but a 180-degree turn about Z. That is the difference
## between one uniform sheet of fog and seven bands of different thickness, two
## of them drifting the other way.
##
## ## An empty file is a valid one
##
## 390 of the 545 shipped `.events` are four bytes holding zero: a scene that
## declares no effects. The C reader returned false for those until it was
## noticed that it was reporting 390 failures that were not failures -- and a
## real one would have been lost among them.
##
## ## No game data ships here
class_name UMK3Events
extends RefCounted

const TRACK_HEADER := 268
const ENTRY_SIZE := 56
const OFF_NAME := 0x000
const OFF_SLOT := 0x0c8
const OFF_NENT := 0x108
const FIXED := 4096.0

class Track extends RefCounted:
	var name := ""                    ## the effect: "gymist1", "MUZZLEFLASH"
	var slot := ""
	var basis := Basis.IDENTITY
	var origin := Vector3.ZERO

	## The placement, ready to hang a node on.
	func to_transform() -> Transform3D:
		return Transform3D(basis, origin)

var tracks: Array[Track] = []
var error := ""


static func _cstr(b: PackedByteArray, at: int, n: int) -> String:
	var end := at
	while end < at + n and end < b.size() and b[end] != 0:
		end += 1
	return b.slice(at, end).get_string_from_ascii()


func load_file(path: String) -> bool:
	tracks.clear()
	error = ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		error = "no " + path
		return false
	var d := f.get_buffer(f.get_length())
	f.close()
	if d.size() < 4:
		error = path + " is too short"
		return false

	var n := d.decode_s32(0)
	if n < 0 or n > 100000:
		error = "%s: %d is not a track count" % [path, n]
		return false
	if n == 0:
		return true                   # a scene with no effects, and that is fine

	var off := 4
	for i in n:
		if off + TRACK_HEADER > d.size():
			error = "%s: track %d does not fit" % [path, i]
			return false
		var tr := Track.new()
		tr.name = _cstr(d, off + OFF_NAME, 64)
		tr.slot = _cstr(d, off + OFF_SLOT, 64)
		var nent := d.decode_s32(off + OFF_NENT)
		off += TRACK_HEADER
		if nent < 0 or off + nent * ENTRY_SIZE > d.size():
			error = "%s: track %d's %d entries do not fit" % [path, i, nent]
			return false

		if nent > 0:
			var e := off + 8
			var m := PackedFloat32Array()
			m.resize(9)
			for k in 9:
				m[k] = float(d.decode_s32(e + k * 4)) / FIXED
			# The engine's 3x3 is ROW-vector; Godot's Basis takes COLUMNS, so
			# passing the rows in as columns is the transpose that crossing
			# conventions needs. Same flip as the skeleton's.
			tr.basis = Basis(Vector3(m[0], m[1], m[2]),
							 Vector3(m[3], m[4], m[5]),
							 Vector3(m[6], m[7], m[8]))
			tr.origin = Vector3(
				float(d.decode_s32(e + 36)) / FIXED,
				float(d.decode_s32(e + 40)) / FIXED,
				float(d.decode_s32(e + 44)) / FIXED)
		off += nent * ENTRY_SIZE
		tracks.append(tr)
	return true
