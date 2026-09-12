## How high off its own origin is each animation frame?
##
## A fighter's y is `G[0xac] - ochar_ground_offsets[char]` -- the STANDING
## height, 139 for Scorpion -- and nothing in the engine changes it when he is
## knocked down. So a lying frame only reaches the floor if the CLIP is
## authored that way: its lowest vertex has to sit 139 units below the origin,
## exactly as the stance's does.
##
## This measures it, so the question stops being a guess.
##
##     godot --headless --path <project> --script umk3/umk3_framey.gd
##
## ## No game data ships here
extends SceneTree

const _Skin := preload("res://umk3/umk3_skin.gd")
const _Paths := preload("res://umk3/umk3_paths.gd")
const _Fighter := preload("res://umk3/umk3_fighter.gd")
const _Ani := preload("res://umk3/umk3_scorpion_ani.gd")


func _init() -> void:
	var skin = _Skin.new()
	if not skin.load_character(_Paths.resolve(""), "SCORPION_STANDARD"):
		printerr(skin.error)
		quit(2)
		return

	# The stance is the reference: whatever it measures IS standing on the
	# floor, because that is what the fight is scaled and grounded against.
	var base := _low(skin, 216)
	var tall := _high(skin, 216) - base
	print("frame 216 (SCSTANCE1)   lowest %.2f  height %.2f  <- the floor"
		% [base, tall])
	print("offsets below are in UNITS and in BODY HEIGHTS")
	print()
	for id in [30, 31, 71]:
		var a: Array = _Ani.ANI[id]
		if a.is_empty():
			continue
		var line := "ani %2d %-14s" % [id, a[0]]
		for f in (a[2] as Array):
			var d := _low(skin, int(f)) - base
			line += "  %d:%+.1f(%+.2fh)" % [f, d, d / tall]
		print(line)


## The highest vertex of one frame.
func _high(skin, frame: int) -> float:
	var pos: PackedVector3Array = skin.skin(skin.pose(frame, frame, 0.0))[0]
	if pos.is_empty():
		return 0.0
	var hi := pos[0].y
	for p in pos:
		hi = maxf(hi, p.y)
	return hi * _Fighter.PLAYER_TO_SCENE


## The lowest vertex of one frame, in the format's own units.
func _low(skin, frame: int) -> float:
	var pos: PackedVector3Array = skin.skin(skin.pose(frame, frame, 0.0))[0]
	if pos.is_empty():
		return 0.0
	var lo := pos[0].y
	for p in pos:
		lo = minf(lo, p.y)
	return lo * _Fighter.PLAYER_TO_SCENE
