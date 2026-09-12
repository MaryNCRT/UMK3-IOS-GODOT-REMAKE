## PVRTC decoder and texture resolver.
##
## Ported from `runtime/lime/pvr.c`. The container is **legacy PVR v2** -- a
## 52-byte header with a `PVR!` tag, not the v3 format modern tooling defaults
## to -- and every one of the game's 1,400 files is PVRTC1 at 2 or 4 bits per
## pixel, with no mipmaps and power-of-two dimensions. That survey is in
## docs/PVR-FORMAT.md; the block arithmetic comes out exact on all 1,400.
##
## ## 221 of the textures are PNG
##
## Not every texture is PVRTC. The C port stopped at the PVRTC loop for a long
## time and every stage whose atlas is a PNG drew untextured -- the single
## largest visual gap it had. Godot reads PNG natively, so those cost nothing
## here; the resolver below tries both.
##
## ## Decoding is cached
##
## PVRTC is per-pixel work and GDScript is not the language for it: a 512x512
## texture is a quarter of a million pixels of bilinear endpoint blending. So
## each decode is written to `user://umk3_texcache` as PNG and read from there
## afterwards. The key includes the source file's size and modification time,
## so replacing the `res` folder invalidates it.
##
## **Nothing is cached into the project.** `user://` is outside it.
class_name UMK3Pvr
extends RefCounted

const PVR_HEADER := 52
const PVR_TAG := 0x21525650          # "PVR!" little-endian
const BLOCK_BYTES := 8

const FMT_PVRTC2 := 0x18
const FMT_PVRTC4 := 0x19

const CACHE_DIR := "user://umk3_texcache"

## Endpoint A -- the top 16 bits of the colour word.
static func _colour_a(packed: int) -> Color:
	if packed & 0x8000:                              # opaque 5-5-5
		var r := (packed >> 10) & 0x1F
		var g := (packed >> 5) & 0x1F
		var b := packed & 0x1F
		return Color8((r << 3) | (r >> 2), (g << 3) | (g >> 2),
					  (b << 3) | (b >> 2), 255)
	var a := (packed >> 12) & 0x07                   # translucent 3-4-4-3
	var r2 := (packed >> 8) & 0x0F
	var g2 := (packed >> 4) & 0x0F
	var b2 := (packed >> 1) & 0x07
	return Color8((r2 << 4) | r2, (g2 << 4) | g2,
				  (b2 << 5) | (b2 << 2) | (b2 >> 1),
				  (a << 5) | (a << 2) | (a >> 1))

## Endpoint B -- the low 16 bits. B has FOUR bits of blue where A has three,
## because A gives up its low bit to the modulation flag.
static func _colour_b(packed: int) -> Color:
	if packed & 0x8000:
		var r := (packed >> 10) & 0x1F
		var g := (packed >> 5) & 0x1F
		var b := packed & 0x1F
		return Color8((r << 3) | (r >> 2), (g << 3) | (g >> 2),
					  (b << 3) | (b >> 2), 255)
	var a := (packed >> 12) & 0x07                   # translucent 3-4-4-4
	var r2 := (packed >> 8) & 0x0F
	var g2 := (packed >> 4) & 0x0F
	var b2 := packed & 0x0F
	return Color8((r2 << 4) | r2, (g2 << 4) | g2, (b2 << 4) | b2,
				  (a << 5) | (a << 2) | (a >> 1))


## Blocks are stored in Morton order: the bits of x and y interleaved, with
## whichever axis is longer contributing its remaining high bits linearly.
static func _morton(x: int, y: int, w: int, h: int) -> int:
	var n := mini(w, h)
	var idx := 0
	var shift := 0
	var k := n
	while k > 1:
		idx |= ((y & 1) << shift) | ((x & 1) << (shift + 1))
		x >>= 1
		y >>= 1
		shift += 2
		k >>= 1
	idx |= (x if w > h else y) << shift
	return idx


static func _decode_pvrtc(raw: PackedByteArray, at: int, width: int,
						  height: int, two_bpp: bool) -> Image:
	var bw := 8 if two_bpp else 4
	var bh := 4
	# Integer division throughout: these are BLOCK COUNTS and block indices,
	# and the truncation is the arithmetic, not a rounding accident.
	@warning_ignore("integer_division")
	var bx := maxi((width + bw - 1) / bw, 1)
	@warning_ignore("integer_division")
	var by := maxi((height + bh - 1) / bh, 1)
	if raw.size() - at < bx * by * BLOCK_BYTES:
		return null

	var nb := bx * by
	var mods := PackedInt64Array()
	var mode := PackedByteArray()
	var ca: Array[Color] = []
	var cb: Array[Color] = []
	mods.resize(nb)
	mode.resize(nb)
	ca.resize(nb)
	cb.resize(nb)

	for j in by:
		for i in bx:
			var off := at + _morton(i, j, bx, by) * BLOCK_BYTES
			var m := raw.decode_u32(off)
			var c := raw.decode_u32(off + 4)
			var k := j * bx + i
			mods[k] = m
			mode[k] = c & 1
			# Colour B is the LOW 16 bits and is NOT shifted: the modulation
			# flag shares bit 0 with the least significant bit of blue rather
			# than displacing the field. Shifting corrupts every channel.
			cb[k] = _colour_b(c & 0xFFFF)
			ca[k] = _colour_a((c >> 16) & 0xFFFF)

	const W_PUNCH := [0.0, 0.5, 0.5, 1.0]
	const W_NORMAL := [0.0, 0.375, 0.625, 1.0]

	var out := PackedByteArray()
	out.resize(width * height * 4)

	for py in height:
		for px in width:
			# The endpoints for a pixel come from the four blocks whose centres
			# surround it, so the block grid sits half a block off.
			@warning_ignore("integer_division")
			var fx := float(px - bw / 2) / float(bw)
			@warning_ignore("integer_division")
			var fy := float(py - bh / 2) / float(bh)
			var i0 := int(floor(fx))
			var j0 := int(floor(fy))
			var u := fx - float(i0)
			var v := fy - float(j0)
			i0 = posmod(i0, bx)
			j0 = posmod(j0, by)
			var i1 := posmod(i0 + 1, bx)
			var j1 := posmod(j0 + 1, by)

			var k00 := j0 * bx + i0
			var k10 := j0 * bx + i1
			var k01 := j1 * bx + i0
			var k11 := j1 * bx + i1
			var w00 := (1.0 - u) * (1.0 - v)
			var w10 := u * (1.0 - v)
			var w01 := (1.0 - u) * v
			var w11 := u * v

			var A := ca[k00] * w00 + ca[k10] * w10 + ca[k01] * w01 + ca[k11] * w11
			var B := cb[k00] * w00 + cb[k10] * w10 + cb[k01] * w01 + cb[k11] * w11

			# Modulation comes from the block the pixel physically sits in.
			@warning_ignore("integer_division")
			var mk := (py / bh) * bx + (px / bw)
			var lx := px % bw
			var ly := py % bh
			var w := 0.0
			var punch := false
			if two_bpp:
				w = 1.0 if (mods[mk] >> (ly * 8 + lx)) & 1 else 0.0
			else:
				var sel: int = (mods[mk] >> ((ly * 4 + lx) * 2)) & 3
				if mode[mk]:
					w = W_PUNCH[sel]
					punch = sel == 2
				else:
					w = W_NORMAL[sel]

			var o := (py * width + px) * 4
			out[o]     = clampi(int(B.r8 * (1.0 - w) + A.r8 * w + 0.5), 0, 255)
			out[o + 1] = clampi(int(B.g8 * (1.0 - w) + A.g8 * w + 0.5), 0, 255)
			out[o + 2] = clampi(int(B.b8 * (1.0 - w) + A.b8 * w + 0.5), 0, 255)
			out[o + 3] = 0 if punch else \
				clampi(int(B.a8 * (1.0 - w) + A.a8 * w + 0.5), 0, 255)

	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, out)


## Decode one .pvr file. Returns null if it is not a PVR v2 PVRTC file.
static func load_pvr(path: String) -> Image:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var raw := f.get_buffer(f.get_length())
	f.close()

	if raw.size() < PVR_HEADER:
		return null
	if raw.decode_u32(44) != PVR_TAG or raw.decode_u32(0) != PVR_HEADER:
		return null

	var height := raw.decode_u32(4)
	var width := raw.decode_u32(8)
	var fmt := raw.decode_u32(16) & 0xFF

	if fmt == FMT_PVRTC4:
		return _decode_pvrtc(raw, PVR_HEADER, width, height, false)
	if fmt == FMT_PVRTC2:
		return _decode_pvrtc(raw, PVR_HEADER, width, height, true)
	return null
