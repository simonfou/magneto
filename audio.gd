extends Node
## Audio in: captures what Spotify plays (Linux, see spotify.gd) or the
## whole PC minus Discord (Windows) into a silent "Capture" bus, and turns
## it every frame into what the visuals read:
##   levels    bass / mid / treble, 0..1, self-calibrating per band
##   kick      jumps to 1 on a beat, then decays
##   presence  overall loudness against the loudest recent passage
## main.gd calls update() once per frame before reading them, so they are
## never a frame late.

signal track_changed(title: String, artist: String)

const Spotify := preload("res://spotify.gd")

# Below this a band counts as silence (no music, or before Spotify is wired).
const SILENCE_DB := -100.0
# Windows build: capture everything the PC plays except this program.
const EXCLUDE_PROCESS := "Discord.exe"
# Without Spotify's track info (Windows), this much silence followed by
# sound counts as a new song.
const GAP_SECONDS := 0.4

var levels := {"bass": 0.0, "mid": 0.0, "treble": 0.0}
var kick := 0.0
var since_kick := 1.0
var kick_count := 0  # beats since the caller last reset it (--meter)
var presence := 0.0

var _tone: bool          # feed a test tone instead of capturing
var _dump_path: String   # log raw band dB per frame here (tuning)
var _t := 0.0
var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _spotify: Spotify
var _player: AudioStreamPlayer
# Windows: system-audio capture from the wincap GDExtension, fed into the
# same analyzer bus through a generator.
var _loopback: RefCounted
var _loop_gen: AudioStreamGeneratorPlayback
var _silent_for := 0.0
# Per-band calibration in dB: a ceiling that sinks and a floor that rises
# slowly, so each band uses its full 0..1 range whatever the track/volume.
var _hi := {"bass": -200.0, "mid": -200.0, "treble": -200.0}
var _lo := {"bass": 0.0, "mid": 0.0, "treble": 0.0}
var _bass_fast := -200.0
var _bass_slow := -200.0
var _rise_avg := 1.0
# Breathing: overall loudness against the loudest recent passage.
var _loud_hi := -200.0
var _test_gen: AudioStreamGeneratorPlayback
var _test_phase := 0.0
var _dump: FileAccess


func _init(tone := false, dump_path := "") -> void:
	_tone = tone
	_dump_path = dump_path


func _ready() -> void:
	if _dump_path != "":
		_dump = FileAccess.open(_dump_path, FileAccess.WRITE)
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "Capture")
	var analyzer := AudioEffectSpectrumAnalyzer.new()
	analyzer.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
	AudioServer.add_bus_effect(idx, analyzer)
	# The analyzer sits before the bus fader, so it still sees the signal;
	# the fader keeps the captured audio from being played back (echo).
	AudioServer.set_bus_volume_db(idx, -80.0)
	_spectrum = AudioServer.get_bus_effect_instance(idx, 0)

	_spotify = Spotify.new()
	_spotify.track_changed.connect(track_changed.emit)
	add_child(_spotify)

	_player = AudioStreamPlayer.new()
	var player := _player
	player.bus = "Capture"
	add_child(player)
	if _tone:
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = 44100.0
		player.stream = gen
		player.play()
		_test_gen = player.get_stream_playback()
	elif OS.get_name() == "Windows":
		# Everything the PC plays except Discord, via the wincap GDExtension
		# (Windows process-loopback API), pushed through a generator so the
		# analyzer bus works exactly as on Linux.
		if ClassDB.class_exists("LoopbackCapture"):
			_loopback = ClassDB.instantiate("LoopbackCapture")
			_loopback.start(EXCLUDE_PROCESS)
			var gen := AudioStreamGenerator.new()
			gen.mix_rate = _loopback.get_mix_rate()
			gen.buffer_length = 0.1
			player.stream = gen
			player.play()
			_loop_gen = player.get_stream_playback()
	else:
		player.stream = AudioStreamMicrophone.new()
		player.play()
		_spotify.capture_enabled = true


## Windows capture status for the level meters ("" elsewhere).
func capture_status() -> String:
	return _loopback.get_status() if _loopback else ""


## Stop capturing before quitting. The audio server needs a moment to drop
## the stream afterwards (see main.gd _quit).
func stop() -> void:
	_player.stop()
	_player.stream = null
	if _loopback:
		_loopback.stop()


func update(delta: float) -> void:
	_t += delta
	if _test_gen:
		_feed_test_tone()
	if _loop_gen:
		_loop_gen.push_buffer(_loopback.take_frames(_loop_gen.get_frames_available()))

	var bands := {"bass": Vector2(30, 160), "mid": Vector2(160, 2000), "treble": Vector2(2000, 12000)}
	var bass_db := -140.0
	for b in bands:
		var m := _spectrum.get_magnitude_for_frequency_range(bands[b].x, bands[b].y)
		var db := linear_to_db(maxf((m.x + m.y) * 0.5, 1e-7))
		if b == "bass":
			bass_db = db
		if _dump:
			_dump.store_string("%.3f,%s,%.2f\n" % [_t, b, db])
		if db < SILENCE_DB:
			levels[b] = lerpf(levels[b], 0.0, 1.0 - exp(-6.0 * delta))
			continue
		if _hi[b] < SILENCE_DB:  # first real sample: start the window here
			_hi[b] = db
			_lo[b] = db - 10.0
		_hi[b] = maxf(db, _hi[b] - delta * 1.5)
		_lo[b] = minf(db, _lo[b] + delta * 1.5)
		# Typical music moves ~10 dB per band; a minimum span keeps a flat
		# passage from flickering between 0 and 1.
		var span := maxf(_hi[b] - _lo[b], 8.0)
		var v := clampf((db - (_hi[b] - span)) / span, 0.0, 1.0)
		v = pow(v, 1.5)  # keep quiet parts quiet
		# Fast attack, slower release.
		var k := 15.0 if v > levels[b] else 4.0
		levels[b] = lerpf(levels[b], v, 1.0 - exp(-k * delta))

	# Presence: broadband loudness against the loudest recent passage (the
	# ceiling sinks only 0.25 dB/s, so a quiet intro or bridge reads quiet).
	var wide := _spectrum.get_magnitude_for_frequency_range(20, 16000)
	var wide_db := linear_to_db(maxf((wide.x + wide.y) * 0.5, 1e-7))
	var target := 0.0
	if wide_db > SILENCE_DB:
		if _loud_hi < SILENCE_DB:
			_loud_hi = wide_db
		_loud_hi = maxf(wide_db, _loud_hi - delta * 0.25)
		target = clampf((wide_db - (_loud_hi - 18.0)) / 18.0, 0.0, 1.0)
	var pk := 2.5 if target > presence else 0.7
	presence = lerpf(presence, target, 1.0 - exp(-pk * delta))

	# Song change by silence gap, when there is no Spotify track info
	# (Windows): a short stretch of digital silence, then sound again.
	if wide_db < SILENCE_DB:
		_silent_for += delta
	else:
		if _silent_for > GAP_SECONDS and not _spotify.has_track_info():
			track_changed.emit("", "")
		_silent_for = 0.0

	# Beat: the bass envelope jumps above its recent level by more than it
	# usually does for this track. Thresholds tuned offline on --dump data
	# (~1.7 beats/s on metal; the analyzer only updates ~21 times/s).
	since_kick += delta
	if bass_db < SILENCE_DB:
		_bass_fast = bass_db
		_bass_slow = bass_db
		kick *= exp(-7.0 * delta)
		return
	if _bass_slow < SILENCE_DB:  # music just started: no fake beat
		_bass_slow = bass_db
		_bass_fast = bass_db
	_bass_fast = lerpf(_bass_fast, bass_db, 1.0 - exp(-60.0 * delta))
	_bass_slow = lerpf(_bass_slow, bass_db, 1.0 - exp(-4.0 * delta))
	var rise := _bass_fast - _bass_slow
	_rise_avg = clampf(lerpf(_rise_avg, absf(rise), 1.0 - exp(-0.5 * delta)), 0.5, 4.0)
	if rise > maxf(1.5, _rise_avg * 1.2) and since_kick > 0.14:
		kick = 1.0
		since_kick = 0.0
		kick_count += 1
	kick *= exp(-7.0 * delta)


func _feed_test_tone() -> void:
	# 70 Hz sine pulsing twice a second: should light up bass and kick.
	var frames := _test_gen.get_frames_available()
	for i in frames:
		_test_phase += 70.0 / 44100.0
		var env := 1.0 if fmod(_test_phase / 70.0, 0.5) < 0.25 else 0.0
		var s := sin(_test_phase * TAU) * 0.5 * env
		_test_gen.push_frame(Vector2(s, s))
