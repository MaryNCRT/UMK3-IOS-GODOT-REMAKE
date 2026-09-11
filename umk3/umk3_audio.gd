## The fight's sounds, from the engine's own sound groups.
##
## Ported from the C project's `runtime/fight_audio.c`.
##
## ## Where the groups come from
##
## Not from a list someone assembled by ear. `tools/sounds.py` recovers them
## from the binary: the `.wav` names are stored inline in `__cstring` as a run
## of NUL-terminated strings with a literal `end_of_list` ending each group, and
## `group_sound`, `ochar_sound`, `tsound_func` and `rsnd_func` all take a group
## number and play one of its members.
##
## The reading is checked against something it cannot control -- **401 of the
## 402 names are real files in `res/audio`** -- and the groups below carry the
## address each starts at, so they can be re-derived rather than trusted.
##
## ## What is still a choice
##
## **Which group goes with which move.** That mapping lives in the per-move
## code -- every `ochar_sound(obj)` call site passes an index in `obj->field24`
## -- and those call sites are in files that are not decompiled. So the group
## CONTENTS are the game's and the ASSIGNMENT is mine, and the two are kept
## visibly apart below.
##
## ## No asset ships here
extends Node

## Transcribed from `python tools/sounds.py <res/audio>`, with the address each
## group starts at.
const GRP_FOOT := ["Foot1", "Foot2", "Foot3", "Foot4"]          # @0017a070
const GRP_BLOCK := ["Block1"]                                   # @0017a0c4
const GRP_FACE := ["Face2"]                                     # @0017a12c
const GRP_BIG3 := ["Bighit3"]                                   # @0017a160
const GRP_BIG12 := ["Bighit1", "Bighit2"]                       # @0017a1e0
const GRP_BODY := ["Body1", "Body2"]                            # @0017a278
const GRP_WHOOSH := ["Whoosh1", "Whoosh2", "Whoosh3", "Bwhoosh2"]  # @0017a310
const GRP_BWHOOSH := ["Bwhoosh1", "Bwhoosh3"]                   # @0017a368
const GRP_FALL := ["Gudfall1", "Gudfall2", "Gudfall3", "Gudfall4"]  # @0017a2ac
## Scorpion's own group, @0017b028. The first two are the voice lines, and the
## names say which: "Scorcome" and "Scorget" are "come here" and "get over
## here".
const GRP_SCORP := ["Scorcome", "Scorget", "Scormask", "Scortele"]

## How many sound effects can overlap. A fighting game plays short one-shot
## voices, so a small ring is enough and a stolen voice is better than a
## missed hit.
const VOICES := 12

var res_dir := ""
var loaded := 0
var missing := 0
var rate := 0

var _snd := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer = null
var _music_stem := ""


func _init(dir: String) -> void:
	res_dir = dir


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	add_child(_music)
	_music.finished.connect(_loop_music)

	for g in [GRP_FOOT, GRP_BLOCK, GRP_FACE, GRP_BIG3, GRP_BIG12, GRP_BODY,
			GRP_WHOOSH, GRP_BWHOOSH, GRP_FALL, GRP_SCORP]:
		for name in g:
			_load(name)
	print("[umk3] audio: %d sounds at %d Hz%s" % [loaded, rate,
		"" if missing == 0 else ("  (%d missing)" % missing)])


## RIFF/WAVE, and only the shape the game actually uses: PCM, one channel,
## 8 bits. Anything else is refused by name rather than mis-decoded -- a 16-bit
## file read as 8-bit is not a quiet bug, it is a scream.
func _load(name: String) -> void:
	if _snd.has(name):
		return
	var path := res_dir.path_join("audio").path_join(name + ".wav")
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		missing += 1
		return
	var d := f.get_buffer(f.get_length())
	f.close()
	if d.size() < 44 or d.slice(0, 4).get_string_from_ascii() != "RIFF" \
			or d.slice(8, 12).get_string_from_ascii() != "WAVE":
		missing += 1
		return

	var ch := 0
	var bits := 0
	var hz := 0
	var at := -1
	var length := 0
	var pos := 12
	while pos + 8 <= d.size():
		var tag := d.slice(pos, pos + 4).get_string_from_ascii()
		var clen := d.decode_u32(pos + 4)
		if tag == "fmt " and clen >= 16:
			if d.decode_u16(pos + 8) != 1:
				missing += 1
				return                      # compressed, refused by name
			ch = d.decode_u16(pos + 10)
			hz = d.decode_u32(pos + 12)
			bits = d.decode_u16(pos + 22)
		elif tag == "data":
			at = pos + 8
			length = mini(int(clen), d.size() - at)
		pos += 8 + int(clen) + (int(clen) & 1)

	if at < 0 or length <= 0 or ch != 1 or bits != 8:
		missing += 1
		return

	# **RIFF 8-bit is UNSIGNED and Godot's FORMAT_8_BITS is SIGNED.** Handing
	# the bytes over unchanged plays the waveform with its zero line at the
	# top of the range: a loud buzz with the sound buried in it.
	var pcm := d.slice(at, at + length)
	for i in pcm.size():
		pcm[i] = (pcm[i] + 128) & 0xFF

	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_8_BITS
	s.mix_rate = hz
	s.stereo = false
	s.data = pcm
	_snd[name] = s
	loaded += 1
	# Every one of these files is 16 kHz. Recorded from the first rather than
	# assumed, so a set that turns out to differ is visible.
	if rate == 0:
		rate = hz


## Pick one member of a group at random, which is what `group_sound` does -- it
## is why a group holds several takes of the same impact.
func play_group(g: Array, gain: float) -> void:
	if g.is_empty():
		return
	var pick: String = g[randi() % g.size()]
	if not _snd.has(pick):
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _snd[pick]
	p.volume_db = linear_to_db(clampf(gain, 0.001, 1.0))
	p.play()


# ============================== the assignment -- CHOSEN, not read
#
# Which group fires for which event. The groups above are the game's; this is
# not. When the `ochar_sound` call sites are decompiled, every one of these
# becomes a measured index and this block goes away.

func swing(heavy: bool) -> void:
	play_group(GRP_BWHOOSH if heavy else GRP_WHOOSH, 0.55)


func hit(heavy: bool, high: bool) -> void:
	if heavy:
		play_group(GRP_BIG12, 0.95)
	else:
		play_group(GRP_FACE if high else GRP_BODY, 0.85)


func block() -> void:
	play_group(GRP_BLOCK, 0.7)


func step() -> void:
	play_group(GRP_FOOT, 0.30)


func land() -> void:
	play_group(GRP_FOOT, 0.55)


func fall() -> void:
	play_group(GRP_FALL, 0.8)


func voice() -> void:
	play_group(GRP_SCORP, 1.0)


## The stage's music. `res/audio/<stem>.mp3`, the same file the engine streams.
func music(stem: String) -> void:
	if stem == "" or stem == _music_stem:
		return
	var path := res_dir.path_join("audio").path_join(stem + ".mp3")
	if not FileAccess.file_exists(path):
		print("[umk3] no music at " + path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var s := AudioStreamMP3.new()
	s.data = f.get_buffer(f.get_length())
	f.close()
	# `loop` on the stream would be the obvious thing, but a game track that
	# was authored with an intro does not loop cleanly from zero; restarting on
	# `finished` is what the C build's platform layer does too.
	_music_stem = stem
	_music.stream = s
	_music.volume_db = linear_to_db(0.5)
	_music.play()


func _loop_music() -> void:
	if _music.stream:
		_music.play()


func stop_music() -> void:
	_music.stop()
	_music_stem = ""
