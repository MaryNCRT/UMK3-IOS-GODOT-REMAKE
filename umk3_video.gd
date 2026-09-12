## The video settings: what they are, how they are applied, and where they live.
##
## **None of this is in the binary.** The original runs at 480x320 on a phone
## with no options at all, so every number here is a PC port's own decision and
## is marked as such. The rule the rest of the project follows -- measure, do
## not invent -- does not apply to a window that the original never had; what
## does apply is that the fight's own coordinates must not move, and they do
## not: the stage and the fighters stay in engine units and only the surface
## they are drawn onto changes.
##
## ## Antialiasing, honestly
##
## Godot's renderer gives 2x, 4x and 8x MSAA and stops there -- there is no 16x
## mode to switch on. The top entry is 8x MSAA with the 3D buffer rendered at
## twice the width and height and scaled down, which is supersampling on top of
## multisampling; it is heavier than 16x MSAA would be and looks better, and it
## is labelled for what it is rather than for the number.
##
## ## Where it is kept
##
## `user://umk3_video.cfg`, next to the bindings, outside the project. Every
## change is written when it is made.
class_name UMK3Video
extends RefCounted

const CFG := "user://umk3_video.cfg"

enum Mode { WINDOWED, BORDERLESS, FULLSCREEN }

const MODE_NAME := ["windowed", "borderless window", "fullscreen"]

## The sizes offered, smallest first. The screen's own size is added on top of
## these at run time, so a display nobody anticipated is still reachable.
const SIZES := [
	Vector2i(1024, 576), Vector2i(1280, 720), Vector2i(1366, 768),
	Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440),
	Vector2i(3200, 1800), Vector2i(3840, 2160),
]

## Antialiasing, in the order the menu cycles it.
const AA_NAME := ["off", "2x MSAA", "4x MSAA", "8x MSAA",
	"8x MSAA + SSAA x2"]
const AA_MSAA := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X,
	Viewport.MSAA_8X, Viewport.MSAA_8X]
const AA_SCALE := [1.0, 1.0, 1.0, 1.0, 2.0]

## 0 means no limit. The rest is the range asked for, at the refresh rates a
## monitor is actually likely to have.
const FPS := [0, 30, 60, 75, 90, 120, 144, 165, 180, 200, 240]

var size := Vector2i(1280, 720)
## Which physical display. On one monitor it is always 0 and the row still
## shows, because a machine can grow a second screen between two runs.
var screen := 0
var mode := Mode.WINDOWED
var aa := 0
var vsync := true
var fps_cap := 0


func _init() -> void:
	load_cfg()


## Every size worth offering on THIS machine: the list above, cut off at the
## CHOSEN screen, with that screen's own size on the end. A 4K monitor beside
## a 1080p one should not be offering 1080p's list.
func sizes() -> Array:
	var full := DisplayServer.screen_get_size(_screen())
	var out: Array = []
	for s in SIZES:
		if s.x <= full.x and s.y <= full.y:
			out.append(s)
	if not out.has(full):
		out.append(full)
	return out


## The chosen display, clamped -- a monitor can be unplugged between two runs
## and a saved index that no longer exists must not black the game out.
func _screen() -> int:
	return clampi(screen, 0, maxi(DisplayServer.get_screen_count() - 1, 0))


func screens() -> int:
	return maxi(DisplayServer.get_screen_count(), 1)


func screen_name() -> String:
	var i := _screen()
	var sz := DisplayServer.screen_get_size(i)
	var hz := DisplayServer.screen_get_refresh_rate(i)
	if hz > 0.0:
		return "monitor %d  (%d x %d @ %d)" % [i + 1, sz.x, sz.y, int(hz)]
	return "monitor %d  (%d x %d)" % [i + 1, sz.x, sz.y]


## Put every setting into effect. Safe to call as often as you like.
func apply() -> void:
	# **The buffer settings need a root Window and the rest does not**, and
	# they are applied separately for exactly that reason: an early return on
	# a missing root used to drop the vertical sync and the frame limit with
	# it, silently, which is the kind of bug that reads as "the setting does
	# nothing".
	var root := Engine.get_main_loop().root as Window

	# **The monitor is chosen before anything else.** Moving a window between
	# screens while it is fullscreen is not something every driver takes
	# kindly to, so it goes back to windowed, moves, and then goes fullscreen
	# again on the display it is now on.
	if DisplayServer.window_get_current_screen() != _screen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_current_screen(_screen())

	# The window: an exclusive fullscreen swap resizes the viewport, and the
	# buffer settings should land on the size that survives it.
	match mode:
		Mode.FULLSCREEN:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS,
				false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		Mode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS,
				true)
			_resize()
		Mode.WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS,
				false)
			_resize()

	var at: int = clampi(aa, 0, AA_NAME.size() - 1)
	if root != null:
		root.msaa_3d = AA_MSAA[at]
		root.scaling_3d_scale = float(AA_SCALE[at])

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync
		else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_cap


## Windowed and borderless both take the chosen size; fullscreen does not, and
## the menu says so rather than silently ignoring the row.
func _resize() -> void:
	DisplayServer.window_set_size(size)
	# Centred on the CHOSEN screen, which on a multi-monitor desktop is an
	# offset into the virtual desktop rather than a position on one display.
	var i := _screen()
	var org := DisplayServer.screen_get_position(i)
	var full := DisplayServer.screen_get_size(i)
	var at := org + (full - size) / 2
	DisplayServer.window_set_position(at)


func fps_name() -> String:
	return "unlimited" if fps_cap == 0 else "%d fps" % fps_cap


func size_name() -> String:
	if mode == Mode.FULLSCREEN:
		var s := DisplayServer.screen_get_size(_screen())
		return "%d x %d  (screen)" % [s.x, s.y]
	return "%d x %d" % [size.x, size.y]


# --------------------------------------------------------------- persistence
func save_cfg() -> void:
	var c := ConfigFile.new()
	c.set_value("video", "width", size.x)
	c.set_value("video", "height", size.y)
	c.set_value("video", "mode", int(mode))
	c.set_value("video", "screen", screen)
	c.set_value("video", "aa", aa)
	c.set_value("video", "vsync", vsync)
	c.set_value("video", "fps", fps_cap)
	c.save(CFG)


func load_cfg() -> void:
	var c := ConfigFile.new()
	if c.load(CFG) != OK:
		# First run: start at whatever the window already is, so nothing jumps.
		size = DisplayServer.window_get_size()
		return
	size = Vector2i(int(c.get_value("video", "width", size.x)),
		int(c.get_value("video", "height", size.y)))
	mode = int(c.get_value("video", "mode", int(mode))) as Mode
	screen = int(c.get_value("video", "screen", screen))
	aa = int(c.get_value("video", "aa", aa))
	vsync = bool(c.get_value("video", "vsync", vsync))
	fps_cap = int(c.get_value("video", "fps", fps_cap))
