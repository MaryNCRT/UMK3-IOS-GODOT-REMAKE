## A stage, on screen, with an orbit camera.
##
## Set `res_dir` in the inspector (or leave it and pass --res on the command
## line) to your own extracted `UMK3.app/res`. NO GAME DATA SHIPS WITH THIS
## PROJECT: the folder is yours and nothing is copied in.
##
##   arrow keys / drag   orbit
##   mouse wheel         zoom
##   [ and ]             previous / next stage
##   SPACE               next scene-graph frame (some stages animate placement)
extends Node3D

const _Stage := preload("res://umk3/umk3_stage.gd")
const UMK3Paths := preload("res://umk3/umk3_paths.gd")

const STAGES := [
	"GRAVEYARD_LEVEL_SCENE", "BALCONY_LEVEL_SCENE", "BELLTOWER_LEVEL_SCENE",
	"BRIDGE_LEVEL_SCENE", "CAVE_LEVEL_SCENE", "JADESDESERT_LEVEL_SCENE",
	"LAIR_LEVEL_SCENE", "NOOBSDORFEN_LEVEL_SCENE", "PIT_LEVEL_SCENE",
	"ROOFTOP_LEVEL_SCENE", "SCISLACBUSOREZ_LEVEL_SCENE",
]

@export_dir var res_dir := ""

var _stage
var _index := 0
var _frame := 0
var _cam: Camera3D
var _yaw := 0.0
var _pitch := -0.15
var _dist := 1.0
var _label: Label


func _ready() -> void:
	res_dir = UMK3Paths.resolve(res_dir)
	if res_dir == "":
		push_error("Set res_dir on the StageViewer node, or pass the path "
			+ "after -- on the command line. It is your own extracted "
			+ "UMK3.app/res; no game data ships with this project.")
		return
	print("[umk3] res: " + res_dir)

	_cam = Camera3D.new()
	_cam.far = 60000.0          # Graveyard's moon is ~27,500 units out
	_cam.near = 1.0
	_cam.fov = 25.0             # GAME_FOV_DEGREES, from the C port
	add_child(_cam)

	var ui := CanvasLayer.new()
	add_child(ui)
	_label = Label.new()
	_label.position = Vector2(12, 8)
	_label.add_theme_font_size_override("font_size", 16)
	ui.add_child(_label)

	_load(0)


func _load(i: int) -> void:
	_index = wrapi(i, 0, STAGES.size())
	_frame = 0
	if _stage:
		_stage.queue_free()
	_stage = _Stage.new()
	add_child(_stage)
	if not _stage.build(res_dir, STAGES[_index], _frame):
		_label.text = "FAILED: " + _stage.error
		return
	_dist = maxf(_stage.reach * 0.9, 10.0)
	_update_label()
	_update_cam()


func _update_label() -> void:
	_label.text = "%d/%d  %s   frame %d   [ ] change stage, SPACE frame" % [
		_index + 1, STAGES.size(), STAGES[_index], _frame]


func _update_cam() -> void:
	# Input arrives even when _ready bailed out for a missing res folder, and
	# a null camera then crashes on every keypress -- which buries the actual
	# error under a stack trace. Guard rather than assume _ready succeeded.
	if _cam == null:
		return
	var b := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	_cam.transform = Transform3D(b, b * Vector3(0, 0, _dist))


func _unhandled_input(e: InputEvent) -> void:
	if _cam == null:
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			get_tree().quit()
		return
	if e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_yaw -= e.relative.x * 0.006
		_pitch = clampf(_pitch - e.relative.y * 0.006, -1.4, 1.4)
		_update_cam()
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(_dist * 0.9, 1.0); _update_cam()
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(_dist * 1.1, 200000.0); _update_cam()
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_BRACKETLEFT:  _load(_index - 1)
			KEY_BRACKETRIGHT: _load(_index + 1)
			KEY_SPACE:
				_frame += 1
				if _stage.scene_graph.num_frames > 0:
					_frame %= _stage.scene_graph.num_frames
				_stage.build(res_dir, STAGES[_index], _frame)
				_update_label()
			KEY_ESCAPE: get_tree().quit()
