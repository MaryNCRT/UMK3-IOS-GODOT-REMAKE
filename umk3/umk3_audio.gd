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
## ## The assignment is MEASURED too, now
##
## It used to be a choice, and it was wrong in ways that could be heard. It is
## not a choice any more, because **the groups have names in the binary**:
## sixteen `_tab_rsnd_*` symbols in `__DATA`, in order, and `rsnd_func(obj, N)`
## takes N as the index into exactly that list.
##
##     0 enemy_boom   1 sk_bonus_win  2 splish      3 stab
##     4 footstep     5 big_block     6 small_block 7 smack
##     8 med_smack    9 klang        10 big_smack  11 rocks
##    12 body_hit    13 ground       14 whoosh     15 big_whoosh
##
## Scanning every call site of `rsnd_func` (0x00057dbc) for the literal each
## one passes then says which sound belongs to which event, by name:
##
##     t_r_hi_punch, t_r_duck_punch, t_r_duck_kickh, t_r_duck_kickl    7 smack
##     t_r_lo_punch, t_r_lo_kick, t_r_sweep, t_r_stick_sweep      12 body_hit
##     t_r_hi_kick, t_r_uppercut, t_r_roundhouse, every t_r_combo 10 big_smack
##     t_r_flip_punch, t_r_flip_kick, t_r_elbow_knee               8 med_smack
##     t_r_tusk_elbow (which is the NINJA elbow's reaction)         3 stab
##     t_r_combo_klang                                             9 klang
##     t_jhp4, t_do_flip_punch, t_do_flip_kick, t_stat_do_duck_*   14 whoosh
##     t_stat_do_hi_kick, t_stat_do_uppercut, _sweep_sounds    15 big_whoosh
##     t_b_punch, t_b_lo_punch, t_b_weak                     6 small_block
##     t_b_hard, t_b_uppercut, t_b_combo_hard                  5 big_block
##
## This port was picking Face2 or Body1 from whether the strike box sat above
## y = 40, and Bighit from whether the damage passed 24. Both of those are now
## gone: the sound comes from the same reaction id the knockback does.
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

# ===================== the character's VOICE, which was missing entirely
#
# A third sound path runs beside `rsnd_func`. Every attack, every jump, every
# reaction also calls `group_sound` (0x000580a4), and that one does
#
#     MKEvent_Add(2, 1, (_ochar_voice_groups[character] << 4) + obj->0x1c, 0)
#
# so it picks the character's VOICE SET and then which kind of noise. Scanning
# its call sites for the index each passes gives the kinds outright:
#
#     0  t_do_flip_kick, t_do_flip_punch, t_do_jumpup_punch, _sweep_sounds,
#        t_stat_do_lo_kick, t_lfly5                              the ATTACK grunt
#     1  t_do_jump_up, t_do_flip                                 the JUMP
#     2  t_r_hi_kick and twenty other t_r_*                      taking a HIT
#     3  _grab_voice                                             a THROW
#     7  run_setup                                               RUNNING
#     9  t_fall_down_pit, t_local_r_laser                        FALLING
#
# And `_ochar_voice_groups` (0x0016f55c) says which set: **Scorpion is 1**, the
# second of the nine, and the nine are the prefixes the group members carry --
# Pb, Vp, Df, Ebl, Jh, Rob, Lk, Am, Sk. So Scorpion speaks with the `Vp*`
# files, and every one of them is a real file in `res/audio`.
#
# **The stride is not uniform** -- `_gs_death` holds one take per voice set and
# `_gs_face_hit_voice` holds three -- so these are taken by NAME rather than by
# arithmetic on the group, and the name is what the check rests on.
const VOICE_ATTACK := ["Vpatt1", "Vpatt2"]      # _gs_attack, index 1
const VOICE_JUMP := ["Vpjump"]                  # _gs_jump
const VOICE_FACE := ["Vpface1", "Vpface2"]      # _gs_face_hit_voice
const VOICE_BODY := ["Vpbody1", "Vpbody2"]
const VOICE_WASTED := ["Vpwast1", "Vpwast2"]    # _gs_wasted
const VOICE_RUN := ["Vprun"]                    # _gs_run
const VOICE_GRAB := ["Vpgrab"]                  # _gs_grab
const VOICE_DEATH := ["Vpdeath"]                # _gs_death
const VOICE_TRIP := ["Vptrip"]                  # _gs_tripped_voice

## `group_sound`'s index -> the files it reaches for Scorpion.
const VOICE := {
	0: VOICE_ATTACK,
	1: VOICE_JUMP,
	2: VOICE_FACE,
	3: VOICE_GRAB,
	7: VOICE_RUN,
	9: VOICE_WASTED,
}

## Two more the fight now needs, in the engine's own order.
const GRP_STAB := ["Stab1", "Bigstab1", "Bigstab2", "Bigstab3"]   # @0017a010
const GRP_KLANG := ["Robball2", "Robball1"]                       # @0017a1a4

## **`_tab_rsnd_*`, by the index `rsnd_func` takes.** Empty where the group is
## real but this build never plays it.
const _Stk := preload("res://umk3/umk3_strikes.gd")

const RSND := {
	3: GRP_STAB,
	4: GRP_FOOT,
	5: GRP_BLOCK,        # big_block
	6: GRP_BLOCK,        # small_block -- both hold the one Block1
	7: GRP_FACE,         # smack
	8: GRP_BIG3,         # med_smack
	9: GRP_KLANG,
	10: GRP_BIG12,       # big_smack
	12: GRP_BODY,        # body_hit
	13: GRP_FALL,        # ground
	14: GRP_WHOOSH,
	15: GRP_BWHOOSH,
}

## The indices, by the name the binary gives them.
const SND_STAB := 3
const SND_FOOT := 4
const SND_BIG_BLOCK := 5
const SND_SMALL_BLOCK := 6
const SND_SMACK := 7
const SND_MED_SMACK := 8
const SND_KLANG := 9
const SND_BIG_SMACK := 10
const SND_BODY := 12
const SND_GROUND := 13
const SND_WHOOSH := 14
const SND_BIG_WHOOSH := 15

## Which `rsnd_func` index each REACTION plays. The key is the reaction id out
## of a strike record's fifth word -- see umk3_strikes.gd.
const REACT_SND := {
	0: SND_BIG_SMACK,    # t_r_hi_kick
	1: SND_BODY,         # t_r_lo_kick
	2: SND_SMACK,        # t_r_hi_punch
	3: SND_BODY,         # t_r_lo_punch
	4: SND_BODY,         # t_r_sweep
	5: SND_SMACK,        # t_r_duck_punch
	6: SND_SMACK,        # t_r_duck_kickh
	7: SND_SMACK,        # t_r_duck_kickl
	8: SND_BIG_SMACK,    # t_r_uppercut
	9: SND_MED_SMACK,    # t_r_elbow_knee
	10: SND_MED_SMACK,   # t_r_flip_kick
	11: SND_MED_SMACK,   # t_r_flip_punch
	12: SND_BIG_SMACK,   # t_r_roundhouse
	45: SND_BODY,        # t_r_slide -- not recovered, the body is the guess
	76: SND_STAB,        # t_r_tusk_elbow, which IS the ninja elbow's
	115: SND_BIG_SMACK,  # t_r_scorp_tele
	120: SND_GROUND,     # t_r_ermac_slam
}

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
			GRP_WHOOSH, GRP_BWHOOSH, GRP_FALL, GRP_SCORP, GRP_STAB, GRP_KLANG,
			VOICE_ATTACK, VOICE_JUMP, VOICE_FACE, VOICE_BODY, VOICE_WASTED,
			VOICE_RUN, VOICE_GRAB, VOICE_DEATH, VOICE_TRIP]:
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

	# **When the data is bundled, Godot has already imported it.** A `.wav`
	# inside the project is converted at import time and the original bytes are
	# NOT exported, so the reader below finds nothing in a packaged build --
	# which is exactly how this shipped silent once. The imported resource is
	# there and is the same sound, so use it.
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is AudioStreamWAV:
			_snd[name] = res
			loaded += 1
			if rate == 0:
				rate = res.mix_rate
			return

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


# ====================== the assignment -- MEASURED, from `rsnd_func`'s index

## Play one of the sixteen `_tab_rsnd_*` tables, by the index the engine uses.
## Everything below is a name for one of these calls.
func rsnd(index: int, gain: float) -> void:
	if RSND.has(index):
		play_group(RSND[index], gain)


## The swing. `t_jhp4` and the flip attacks take 14; `t_stat_do_hi_kick`,
## `t_stat_do_uppercut` and `_sweep_sounds` take 15.
func swing(heavy: bool, voice := true) -> void:
	rsnd(SND_BIG_WHOOSH if heavy else SND_WHOOSH, 0.55)
	# Every move proc that takes a whoosh takes a `group_sound 0` beside it --
	# every one except `t_stat_do_uppercut`, which takes the whoosh alone.
	if voice:
		group_voice(0, 0.7)


## The specials' own lines.
##
## `tl_do_scorp_tele` calls `ochar_sound` with 12 and the spear's procs call
## nothing a scan can see, so **the index is not recovered** -- `ochar_sound`
## goes through `MKEvent_Add(2, 3, ...)` and that subtype's table has not been
## found. What IS unambiguous is the names: Scorpion's own group at 0x0017b028
## holds `Scorcome`, `Scorget`, `Scormask` and `Scortele`, and a teleport and a
## "get over here" do not need an index to be identified.
func special(which: int) -> void:
	match which:
		1:                                   # SP_SPEAR
			play_group(["Scorget"], 1.0)
		2:                                   # SP_TELEPUNCH
			play_group(["Scortele"], 1.0)
		_:
			play_group(GRP_SCORP, 1.0)


## `group_sound`: the character's own voice, by the index its call sites pass.
func group_voice(index: int, gain := 0.85) -> void:
	if VOICE.has(index):
		play_group(VOICE[index], gain)


## The impact, from the strike's own reaction -- and the grunt that goes with
## it. **Both**, because the engine plays both: every `t_r_*` calls
## `rsnd_func` for the thump and `group_sound` with 2 for the voice.
func hit_react(reaction: int) -> void:
	rsnd(int(REACT_SND.get(reaction, SND_SMACK)), 0.9)
	group_voice(2)


## **A blocked hit, and the inference is gone.**
##
## The low byte of the strike record's fifth word indexes `_block_xfers`
## (0x001671d8), 24 procs, and the first thing each one does -- or does not do
## -- is call `rsnd_func`. Read off all 24:
##
##     5 big_block     t_b_hard, t_b_uppercut, t_b_hard_ken_masters,
##                     t_b_duck_hit_hard, t_b_combo, t_b_combo_hard,
##                     and t_b_knee_elbow through its tail into t_b_combo
##     6 small_block   t_b_weak, t_b_sweep, t_b_duck_hit_soft,
##                     t_b_weak_no_masters, t_b_punch, t_b_lo_punch
##     nothing         the other eleven, and the silence is measured too
##
## So the ninja set lands as: high kick and low kick big, jab and low punch
## small, sweep small, uppercut big, the jumps and the roundhouse big, knee and
## elbow big, the duck punch small and the duck high kick big. This used to be
## guessed off the impact sound and had several of them backwards.
func block_hit(block_idx: int) -> void:
	if _Stk.BLOCK_BIG.has(block_idx):
		rsnd(SND_BIG_BLOCK, 0.7)
	elif _Stk.BLOCK_SMALL.has(block_idx):
		rsnd(SND_SMALL_BLOCK, 0.7)


func block() -> void:
	rsnd(SND_SMALL_BLOCK, 0.7)


func step() -> void:
	rsnd(SND_FOOT, 0.30)


func land() -> void:
	rsnd(SND_FOOT, 0.55)


## `t_do_jump_up` calls `group_sound` with 1.
func jump() -> void:
	group_voice(1, 0.7)


## `t_stung_by_scorpion` -- being harpooned -- calls `rsnd_func` with 3, the
## STAB table. Not a voice: this port was playing Scorpion's own line on the
## man who got hit.
func speared() -> void:
	rsnd(SND_STAB, 0.95)
	group_voice(2)


func fall() -> void:
	rsnd(SND_GROUND, 0.8)


## The character's own voice. `t_spear0` -- the reaction to being speared --
## reaches for `his_ochar_sound` and `group_sound` rather than one of the
## sixteen, so a speared fighter shouts rather than being smacked.
func voice() -> void:
	play_group(GRP_SCORP, 1.0)


## The stage's music. `res/audio/<stem>.mp3`, the same file the engine streams.
func music(stem: String) -> void:
	if stem == "" or stem == _music_stem:
		return
	var path := res_dir.path_join("audio").path_join(stem + ".mp3")
	var s: AudioStream = null
	# Same as the sounds: a bundled mp3 is an imported resource, not a file.
	if ResourceLoader.exists(path):
		s = load(path)
	if s == null:
		if not FileAccess.file_exists(path):
			print("[umk3] no music at " + path)
			return
		var f := FileAccess.open(path, FileAccess.READ)
		var mp3 := AudioStreamMP3.new()
		mp3.data = f.get_buffer(f.get_length())
		f.close()
		s = mp3
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
