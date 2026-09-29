class_name GameAudio
extends Node
## Procedural sound: every effect and the ambient lute music is synthesized into PCM buffers.

const RATE := 16000

var sounds := {}
var players: Array = []
var music_players: Array = []
var _notes := {}
var next_note := 0.0
var clock := 0.0


func setup() -> GameAudio:
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Music")
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.7
		rev.wet = 0.35
		AudioServer.add_bus_effect(idx, rev)
		var dl := AudioEffectDelay.new()
		dl.tap1_delay_ms = 320
		dl.tap1_level_db = -9
		AudioServer.add_bus_effect(idx, dl)
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		music_players.append(p)
	_build()
	return self


func set_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))


func set_music(v: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(v, 0.0001)))


# ------------------------------------------------ synthesis
func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE) + 1)
	return b


func _env(t: float, dur: float) -> float:
	var a := minf(1.0, t / 0.01)
	return a * exp(-5.0 * t / dur)


func _tone(b: PackedFloat32Array, freq: float, dur: float, wave := "sine", vol := 0.2, slide := 0.0, delay := 0.0) -> void:
	var start := int(delay * RATE)
	var n := int(dur * RATE)
	var phase := 0.0
	for i in n:
		if start + i >= b.size():
			break
		var t := float(i) / RATE
		var f := freq * pow(maxf(20.0, freq + slide) / freq, t / dur) if slide != 0.0 else freq
		phase += f / RATE
		var ph := fmod(phase, 1.0)
		var s: float
		match wave:
			"square":
				s = 1.0 if ph < 0.5 else -1.0
			"saw":
				s = ph * 2.0 - 1.0
			"tri":
				s = 4.0 * absf(ph - 0.5) - 1.0
			_:
				s = sin(ph * TAU)
		b[start + i] += s * vol * _env(t, dur)


## band-limited noise via a state-variable filter; kind = low | band | high
func _noise(b: PackedFloat32Array, dur: float, freq := 1000.0, q := 1.0, vol := 0.3, kind := "band", slide := 0.0, delay := 0.0) -> void:
	var start := int(delay * RATE)
	var n := int(dur * RATE)
	var low := 0.0
	var band := 0.0
	var damp := 1.0 / maxf(0.5, q)
	for i in n:
		if start + i >= b.size():
			break
		var t := float(i) / RATE
		var f := freq * pow(maxf(40.0, freq + slide) / freq, t / dur) if slide != 0.0 else freq
		var fc := minf(1.2, 2.0 * sin(PI * minf(f, RATE * 0.45) / RATE))
		var x := randf() * 2.0 - 1.0
		low += fc * band
		var high := x - low - damp * band
		band += fc * high
		var s := band if kind == "band" else (low if kind == "low" else high)
		b[start + i] += s * vol * exp(-4.0 * t / dur)


func _stream(b: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(b.size() * 2)
	for i in b.size():
		bytes.encode_s16(i * 2, int(clampf(b[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


func _build() -> void:
	var b: PackedFloat32Array
	b = _buf(0.2)
	_noise(b, 0.18, 600, 0.8, 0.5, "band", 1800)
	sounds.swing = _stream(b)
	b = _buf(0.15)
	_noise(b, 0.12, 300, 1, 0.9, "low")
	_tone(b, 90, 0.12, "sine", 0.4, -40)
	sounds.hit = _stream(b)
	b = _buf(0.12)
	_noise(b, 0.1, 2500, 3, 0.5)
	_tone(b, 300, 0.08, "square", 0.08, -150)
	sounds.hit_bone = _stream(b)
	b = _buf(0.2)
	_tone(b, 180, 0.15, "tri", 0.3, -80)
	_noise(b, 0.12, 3000, 2, 0.2, "high")
	sounds.bow = _stream(b)
	b = _buf(0.55)
	_noise(b, 0.5, 400, 1, 0.5, "low", 800)
	_tone(b, 120, 0.4, "saw", 0.1, 80)
	sounds.spell_fire = _stream(b)
	b = _buf(0.25)
	_tone(b, 1200, 0.2, "square", 0.1, -900)
	_noise(b, 0.15, 4000, 1, 0.25, "high")
	sounds.spell_spark = _stream(b)
	b = _buf(0.3)
	_tone(b, 500, 0.25, "tri", 0.2, 300)
	_noise(b, 0.2, 1500, 2, 0.2)
	sounds.spell_nature = _stream(b)
	b = _buf(0.9)
	_noise(b, 0.8, 200, 0.7, 1.0, "low", -150)
	_tone(b, 60, 0.6, "sine", 0.5, -30)
	sounds.boom = _stream(b)
	b = _buf(0.6)
	for i in 3:
		_tone(b, [523.0, 659.0, 784.0][i], 0.4, "sine", 0.18, 0, i * 0.08)
	sounds.heal = _stream(b)
	b = _buf(0.25)
	_noise(b, 0.2, 800, 2, 0.3, "band", -500)
	sounds.fizzle = _stream(b)
	b = _buf(0.25)
	_tone(b, 160, 0.2, "saw", 0.2, -80)
	_noise(b, 0.1, 500, 1, 0.4, "low")
	sounds.hurt = _stream(b)
	b = _buf(0.12)
	_noise(b, 0.1, 900, 2, 0.6)
	_tone(b, 200, 0.08, "square", 0.08, -100)
	sounds.bite = _stream(b)
	b = _buf(0.55)
	_tone(b, 110, 0.5, "saw", 0.08, -30)
	sounds.growl_wolf = _stream(b)
	b = _buf(0.45)
	_noise(b, 0.4, 1200, 8, 0.25)
	sounds.growl_skeleton = _stream(b)
	b = _buf(0.35)
	_tone(b, 220, 0.3, "square", 0.06, -100)
	sounds.growl_goblin = _stream(b)
	b = _buf(0.08)
	_noise(b, 0.07, 1400, 0.8, 0.12)
	sounds.step = _stream(b)
	b = _buf(0.08)
	_noise(b, 0.06, 400, 2, 0.3)
	sounds.step_wood = _stream(b)
	b = _buf(0.16)
	_noise(b, 0.15, 900, 1, 0.2, "low")
	sounds.step_water = _stream(b)
	b = _buf(0.12)
	_noise(b, 0.1, 800, 1, 0.2)
	sounds.jump = _stream(b)
	b = _buf(0.3)
	_tone(b, 1320, 0.08, "square", 0.08)
	_tone(b, 1760, 0.18, "square", 0.08, 0, 0.07)
	sounds.coin = _stream(b)
	b = _buf(0.22)
	_tone(b, 660, 0.1, "tri", 0.18)
	_tone(b, 990, 0.12, "tri", 0.18, 0, 0.06)
	sounds.pickup = _stream(b)
	b = _buf(0.35)
	for i in 3:
		_tone(b, 300 + i * 60, 0.08, "sine", 0.2, 100, i * 0.1)
	sounds.drink = _stream(b)
	b = _buf(0.05)
	_tone(b, 900, 0.04, "square", 0.06)
	sounds.click = _stream(b)
	b = _buf(0.3)
	_noise(b, 0.2, 300, 1, 0.6, "low")
	_noise(b, 0.1, 1500, 1, 0.2, "band", 0, 0.05)
	sounds.till = _stream(b)
	b = _buf(0.8)
	for i in 5:
		_tone(b, [392.0, 523.0, 659.0, 784.0, 1046.0][i], 0.35, "tri", 0.2, 0, i * 0.09)
	sounds.levelup = _stream(b)
	b = _buf(1.0)
	for i in 6:
		_tone(b, [523.0, 659.0, 784.0, 1046.0, 784.0, 1046.0][i], 0.3, "tri", 0.18, 0, i * 0.12)
	sounds.quest = _stream(b)
	b = _buf(1.5)
	for i in 4:
		_tone(b, [392.0, 330.0, 262.0, 196.0][i], 0.6, "tri", 0.2, 0, i * 0.25)
	sounds.die = _stream(b)
	b = _buf(0.6)
	_tone(b, 200, 0.3, "saw", 0.08, 100)
	for i in 3:
		_tone(b, [784.0, 988.0, 1175.0][i], 0.3, "tri", 0.15, 0, 0.25 + i * 0.08)
	sounds.chest = _stream(b)


func play(name: String, vol := 1.0) -> void:
	if not sounds.has(name):
		return
	for p in players:
		if not p.playing:
			p.stream = sounds[name]
			p.volume_db = linear_to_db(vol)
			p.pitch_scale = randf_range(0.94, 1.06)
			p.play()
			return


func growl(model: String) -> void:
	play("growl_" + model)


# ------------------------------------------------ generative music
func _pluck(freq: float, mood: String) -> AudioStreamWAV:
	var key := "%s|%d" % [mood, int(freq)]
	if _notes.has(key):
		return _notes[key]
	var dur := 2.2 if mood == "night" else 1.4
	var b := _buf(dur)
	_tone(b, freq, dur, "saw" if mood == "danger" else "tri", 0.12)
	_tone(b, freq * 2.0, dur * 0.6, "sine", 0.03)
	# soften the harmonics like a plucked string
	var lp := 0.0
	for i in b.size():
		var k := 0.25 * exp(-2.5 * float(i) / b.size()) + 0.05
		lp += (b[i] - lp) * k
		b[i] = lp * 1.6
	var s := _stream(b)
	_notes[key] = s
	return s


func update_music(dt: float, mood: String) -> void:
	clock += dt
	if clock < next_note:
		return
	var scales := {
		"day": [293.66, 329.63, 369.99, 440.0, 493.88, 587.33, 659.25, 739.99],
		"night": [220.0, 261.63, 293.66, 329.63, 392.0, 440.0, 523.25],
		"danger": [146.83, 155.56, 196.0, 207.65, 220.0, 293.66],
	}
	var sc: Array = scales.get(mood, scales.day)
	var n: float = sc[randi() % sc.size()]
	_music(_pluck(n, mood), 1.0)
	if randf() < 0.3:
		_music(_pluck(sc[0] / 2.0, mood), 0.8)
	var gap := 0.3 + randf() * 0.3 if mood == "danger" else (0.9 + randf() * 1.5 if mood == "night" else 0.35 + randf() * 0.7)
	next_note = clock + gap * (3.0 if randf() < 0.15 else 1.0)


func _music(s: AudioStream, vol: float) -> void:
	for p in music_players:
		if not p.playing:
			p.stream = s
			p.volume_db = linear_to_db(vol)
			p.play()
			return
