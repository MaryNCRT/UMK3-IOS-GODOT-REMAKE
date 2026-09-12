## The health bars, out of the game's own art and laid out from a picture of
## the game itself.
##
## ## The sprites
##
## `HUD_TPAGE.PNG` is a 256x256 page and the bars are the only thing on it.
## Reading the rows of it gives four sprites exactly:
##
##     x   0..191  y  0..19   192x20   the LIFE bar -- a blue gradient inside
##                                     a one-pixel yellow border
##     x   0.. 63  y 20..27    64x8    the GREEN bar, the run meter
##     x   0.. 31  y 32..51    32x20   the DAMAGE bar -- dark red into orange,
##                                     bordered, and exactly as TALL as the
##                                     life bar because it is drawn over it
##     x  32.. 63  y 32..38    32x7    a flat red strip, the run meter's other
##                                     colour: as tall as the green one
##
## **The last two share rows and that was a bug.** Reading the band y 32..51 as
## one 64-wide sprite -- which is what this did -- straddles both of them, so
## stretching it across a bar drew the damage gradient for the first half and
## the flat red for the second, with a hard seam down the middle. Going column
## by column shows the split at x 32 cleanly: the left half has a yellow border
## on row 32 and the right half does not.
##
## ## What each one IS
##
## The first attempt had it backwards -- green as the life fill on a red
## remainder -- and the reference picture settles it:
##
##   * **The blue 192x20 bar IS the life.** The character's name is printed
##     INSIDE it, and the red is drawn over what he has LOST, growing from the
##     inner end toward the outer. Blue means health.
##   * **The green 64x8 bar is the RUN meter**, underneath and a third of the
##     width -- 64 against 192, which is why it is authored at that size.
##
## And the binary agrees in the one place it can: `_Health` (0x0014fa64) is
## `{100, 100}`, and the symbol immediately after it is **`_RunBar`
## (0x0014fa6c), also `{100, 100}`** -- two players, two meters, a hundred
## each. The run bar exists; it is not something invented to use up the page.
##
## ## What is still chosen
##
## Where on the screen they sit. `DrawHUD` is nine kilobytes of layout that has
## not been decompiled, so the placement is read off the picture: mirrored
## pairs along the top, the name inside the bar in bold italic capitals, the
## run meter under the outer end. When `DrawHUD` is read, only this block
## changes.
##
## The drain is the other one: a hit takes the health at once and the bar
## follows it down over a few frames. `bar_reducer` (0x00059154) is the
## engine's version and is not decompiled either.
##
## ## No asset ships here
extends Control

## The sprites, as rectangles in HUD_TPAGE.PNG. Measured, see above.
const SPR_LIFE := Rect2(0, 0, 192, 20)
const SPR_GREEN := Rect2(0, 20, 64, 8)
const SPR_DAMAGE := Rect2(0, 32, 32, 20)
const SPR_RUN_RED := Rect2(32, 32, 32, 7)

const BAR_W := 192.0
const BAR_H := 20.0
## The run meter, at the size it is authored: a third of the life bar.
const RUN_W := 64.0
const RUN_H := 8.0
## The yellow border inside the life sprite, one pixel top and bottom.
const BORDER := 1.0

## The screen the layout is written against. Everything scales from it.
const BASE_W := 480.0
const BASE_H := 320.0

## How fast the bar catches up with the number, in health points a frame.
const DRAIN := 1.5

## The name plate: capitals, leaning, white over a hard shadow. The original
## uses a bitmap font this port does not have, so it is the fallback font
## SKEWED -- the slant is the thing about that lettering that reads at a
## glance, and it costs one matrix.
const ITALIC := 0.22

var tex: Texture2D = null
var health := [100, 100]
var run := [100, 100]
var wins := [0, 0]
var names := ["SCORPION", "SCORPION"]
var shown := [100.0, 100.0]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# **NEAREST, and it is not a preference.** The bar is a 192x20 sprite blown
	# up two and a bit times, and its border is ONE pixel of yellow. Bilinear
	# smears that border into the blue and, worse, pulls in the green bar that
	# sits directly under it on the page -- the sprites are packed edge to edge
	# with no gutter, so any filtering at all bleeds one into the next.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func setup(textures) -> void:
	tex = textures.get_texture("HUD_TPAGE.???")


## One game frame of the bar chasing the number.
func tick() -> void:
	for i in 2:
		var want := float(health[i])
		if shown[i] > want:
			shown[i] = maxf(want, shown[i] - DRAIN)
		elif shown[i] < want:
			shown[i] = minf(want, shown[i] + DRAIN)
	queue_redraw()


func reset() -> void:
	shown = [100.0, 100.0]


func _draw() -> void:
	if tex == null:
		return
	var vp := get_viewport_rect().size
	var s := minf(vp.x / BASE_W, vp.y / BASE_H)
	var w := BAR_W * s
	var h := BAR_H * s
	var margin := 6.0 * s
	var top := 5.0 * s

	for i in 2:
		# Player one's bar is on the left and player two's on the right; the
		# pair is mirrored about the middle of the screen.
		var mirrored := i == 1
		var x: float = margin
		if mirrored:
			x = vp.x - margin - w
		var frac: float = clampf(shown[i] / 100.0, 0.0, 1.0)
		var bar := Rect2(x, top, w, h)
		var under := Rect2(x, top + h + 2.0 * s, w, RUN_H * s)
		_life(bar, frac, mirrored, s)
		_name(names[i], bar, mirrored, s)
		_run(under, clampf(float(run[i]) / 100.0, 0.0, 1.0), mirrored)
		_wins(under, wins[i], mirrored, s)


## The life bar: the blue sprite whole, then the red over what has been lost.
##
## The red grows from the INNER end -- the middle of the screen -- toward the
## outer, which is what the reference shows and what puts the two fighters'
## damage side by side where it can be compared at a glance.
func _life(r: Rect2, frac: float, mirrored: bool, s: float) -> void:
	draw_texture_rect_region(tex, r, SPR_LIFE)
	if frac >= 1.0:
		return
	# **Full height, inset in X**, and both halves of that are measured:
	#
	#     the LIFE sprite has yellow on all four edges -- x0 and x191 are
	#     (252,249,108) on every row
	#     the DAMAGE sprite has yellow on rows 32 and 51 only; its x0 and x31
	#     are the gradient
	#
	# So the damage bar is drawn to fit INSIDE the life bar's left and right
	# borders, and its own top and bottom borders land exactly on the life
	# bar's. Drawing it the full width ate the border at the outer end, which
	# is the broken edge that was visible.
	var b := BORDER * s
	var span := r.size.x - 2.0 * b
	var lost := span * (1.0 - frac)
	var lx: float = r.position.x + b + span - lost
	if mirrored:
		lx = r.position.x + b
	draw_texture_rect_region(tex,
		Rect2(lx, r.position.y, lost, r.size.y), SPR_DAMAGE)


## The name, inside the bar.
func _name(text: String, r: Rect2, mirrored: bool, s: float) -> void:
	var font := ThemeDB.fallback_font
	var size := int(maxf(11.0, 13.0 * s))
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pad := 7.0 * s
	var x: float = r.position.x + pad
	if mirrored:
		x = r.position.x + r.size.x - pad - tw
	var y: float = r.position.y + (r.size.y + float(size)) * 0.5 - 2.0 * s

	# Skew about the baseline, so the letters lean without drifting off it.
	draw_set_transform_matrix(Transform2D(
		Vector2(1.0, 0.0), Vector2(-ITALIC, 1.0), Vector2(x, y)))
	# **Bold by outline.** The fallback font has one weight and the original's
	# name plate is heavy, so the glyphs are grown: a black outline for the
	# edge the picture has, then a WHITE outline of its own, which is what
	# actually thickens the strokes, then the fill.
	var edge := maxf(3.0, 3.0 * s)
	var weight := maxf(1.0, 1.6 * s)
	draw_string_outline(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, size, int(edge), Color(0, 0, 0, 0.95))
	draw_string_outline(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, size, int(weight), Color(1, 1, 1))
	draw_string(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
		Color(1, 1, 1))
	draw_set_transform_matrix(Transform2D.IDENTITY)


## The run meter, a third of the life bar's width, hard against the outer end.
func _run(r: Rect2, frac: float, mirrored: bool) -> void:
	var w := r.size.x / (BAR_W / RUN_W)
	var x: float = r.position.x
	if mirrored:
		x = r.position.x + r.size.x - w
	# Its empty part is the flat red strip that sits beside the damage bar on
	# the page -- 32x7, the same height as the green one, which is what says
	# the two belong together.
	draw_texture_rect_region(tex, Rect2(x, r.position.y, w, r.size.y),
		SPR_RUN_RED)
	if frac <= 0.0:
		return
	var fw := w * frac
	var fx: float = x
	if mirrored:
		fx = x + w - fw
	draw_texture_rect_region(tex, Rect2(fx, r.position.y, fw, r.size.y),
		SPR_GREEN)


## The round counter, beside the run meter: one square per round won, two
## rounds to a match, which is Mortal Kombat's own rule.
func _wins(r: Rect2, n: int, mirrored: bool, s: float) -> void:
	var d := 8.0 * s
	var gap := 4.0 * s
	var runw := r.size.x / (BAR_W / RUN_W)
	var x: float = r.position.x + runw + gap
	if mirrored:
		x = r.position.x + r.size.x - runw - gap - (d * 2.0 + gap)
	for i in 2:
		var box := Rect2(x + float(i) * (d + gap), r.position.y, d, d)
		draw_rect(box, Color(0.85, 0.1, 0.05) if i < n
			else Color(0.1, 0.12, 0.3), true)
		draw_rect(box, Color(0.99, 0.98, 0.42), false, maxf(1.0, s))
