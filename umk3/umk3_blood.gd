## Blood, from the engine's own event.
##
## ## Where it comes from
##
## `create_blood_proc` (0x0005877c) takes the amount out of `obj->0x1c`,
## **caps it at 12**, and calls `mk3_bloodevent` (0x00031d0c):
##
##     r2 = GrObj + 0x4c * player          the victim's own record
##     x  = (uint16)part->0x0e
##     y  = (uint16)part->0x12
##     packed = y | (x << 16)
##     [0x0016565c][player] = amount
##     MKEvent_Add(0, player, packed, ...)
##
## So the blood is spawned **at the victim's own position**, event type 0, with
## a per-player amount. The amount is what each reaction passes, and scanning
## every call site of `create_blood_proc` gives it per reaction -- see
## umk3_fight.gd's BLOOD.
##
## **Not every hit bleeds.** `t_r_lo_punch`, `t_r_lo_kick`, `t_r_sweep`, the
## three `t_r_duck_*`, `t_r_roundhouse`, both `t_r_flip_*`, `t_r_elbow_knee`
## and `t_r_tusk_elbow` never call it at all. That is the finding, not an
## omission: a jab to the face draws blood and a sweep to the legs does not.
##
## ## What is drawn
##
## `BLOODNEW.PNG` is a 32x32 dark-red blob with an alpha channel -- one
## droplet. The engine's own particle motion is in the event handler and has
## not been decompiled, so **the spread, the speed and the life below are
## chosen**; the count and the spawn point are not.
##
## ## No asset ships here
extends Node3D

## How long a droplet lives, in game frames.
const LIFE := 26
## How fast it leaves, in engine units a frame, and how far the spread goes.
const SPEED := 2.6
const SPREAD := 1.8
## The same 0.5 the rest of the fight falls at -- `t_do_jump_up`'s gravity.
const GRAVITY := 0.5
## One droplet, in engine units.
const SIZE := 9.0

## The engine caps the amount at twelve, so twelve is the most that can ever be
## in flight from one hit; a few hits can overlap.
const MAX := 48

var tex: Texture2D = null
var _mesh: MeshInstance3D = null
var _x := PackedFloat32Array()
var _y := PackedFloat32Array()
var _vx := PackedFloat32Array()
var _vy := PackedFloat32Array()
var _life := PackedInt32Array()
var _n := 0


func setup(textures) -> void:
	tex = textures.get_texture("BLOODNEW.???")
	_mesh = MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	if tex:
		mat.albedo_texture = tex
	_mesh.material_override = mat
	add_child(_mesh)
	_x.resize(MAX)
	_y.resize(MAX)
	_vx.resize(MAX)
	_vy.resize(MAX)
	_life.resize(MAX)


## `mk3_bloodevent`: `amount` droplets at the victim's own x and y.
##
## `facing` is which way the blood goes -- away from whoever landed the hit,
## which is the one thing about the direction that is not arbitrary.
func spawn(x: float, y: float, amount: int, facing: int) -> void:
	if tex == null:
		return
	for i in mini(amount, 12):
		var at := _free()
		if at < 0:
			return
		_x[at] = x
		_y[at] = y
		_vx[at] = (SPEED + randf() * SPREAD) * float(facing)
		_vy[at] = -(SPEED * 0.5 + randf() * SPREAD)
		_life[at] = LIFE
		_n = maxi(_n, at + 1)


func _free() -> int:
	for i in MAX:
		if _life[i] <= 0:
			return i
	return -1


## One game frame. Engine units, like everything else the fight counts in.
func tick() -> void:
	for i in _n:
		if _life[i] <= 0:
			continue
		_life[i] -= 1
		_vy[i] += GRAVITY
		_x[i] += _vx[i]
		_y[i] += _vy[i]


func clear() -> void:
	for i in MAX:
		_life[i] = 0
	_n = 0


## Rebuild the droplets as one mesh. `to_scene` turns an engine x into a scene
## x and `floor_y` is where the engine's y reads zero, so this stays in the
## fight's own coordinates and cannot drift from them.
func draw(units: float, floor_y: float) -> void:
	if _mesh == null:
		return
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var h := SIZE * units * 0.5
	for i in _n:
		if _life[i] <= 0:
			continue
		var cx := _x[i] * units
		var cy := (floor_y - _y[i]) * units
		# Fading out by shrinking, which costs nothing and reads as a droplet
		# drying up rather than blinking off.
		var s := h * minf(1.0, float(_life[i]) / float(LIFE) * 2.0)
		v.append(Vector3(cx - s, cy - s, 0))
		v.append(Vector3(cx + s, cy - s, 0))
		v.append(Vector3(cx + s, cy + s, 0))
		v.append(Vector3(cx - s, cy - s, 0))
		v.append(Vector3(cx + s, cy + s, 0))
		v.append(Vector3(cx - s, cy + s, 0))
		uv.append(Vector2(0, 1))
		uv.append(Vector2(1, 1))
		uv.append(Vector2(1, 0))
		uv.append(Vector2(0, 1))
		uv.append(Vector2(1, 0))
		uv.append(Vector2(0, 0))
	if v.is_empty():
		_mesh.mesh = null
		return
	var arrays := []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = v
	arrays[ArrayMesh.ARRAY_TEX_UV] = uv
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh.mesh = am
