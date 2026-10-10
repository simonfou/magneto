extends Node3D
## Magnetosphere-style visualizer. Everything is built in code so the scene
## file stays trivial. Audio comes straight from whatever
## Spotify is playing, analysed into bass / mid / treble.
## Godot opens the default mic (no way to pick another app's stream) and
## _route_to_spotify() rewires that capture port onto Spotify with pw-link.
##
## Keys: F or F11 = fullscreen, D = level meters, Esc = quit.
## CLI (after `--`): --shot=<png> [--frames=N]  save a frame and quit
##                   --selftest                 feed a test tone, print levels, quit
##                   --meter                    print live capture levels, quit

const NODE_COUNT := 4
const PALETTE: Array[Color] = [
	Color(0.25, 0.45, 1.0),   # deep blue
	Color(0.15, 0.85, 1.0),   # cyan
	Color(0.85, 0.3, 1.0),    # magenta
	Color(1.0, 0.5, 0.15),    # orange
]
# PipeWire node names (pw-link port prefixes). Ours is the project name.
const SPOTIFY_NODE := "spotify"
const OUR_NODE := "magneto"
# Seconds between checks that Spotify is still wired in (Spotify restarted,
# WirePlumber relinked the mic, ...).
const ROUTE_CHECK_EVERY := 3.0

var _process_mat: ShaderMaterial
var _draw_mat: ShaderMaterial
var _camera: Camera3D
var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _hud: Label

var _t := 0.0
var _levels := {"bass": 0.0, "mid": 0.0, "treble": 0.0}
var _peaks := {"bass": 0.3, "mid": 0.3, "treble": 0.3}
var _bass_avg := 0.0
var _kick := 0.0
var _since_kick := 1.0
var _centroid := Vector3.ZERO
var _route_timer := 0.0
var _capturing := false

var _args := {}
var _frame := 0
var _test_gen: AudioStreamGeneratorPlayback
var _test_phase := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_build_environment()
	_build_camera()
	_build_particles()
	_build_audio()
	_build_hud()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in range(1, 7):
		env.set_glow_level(i, 1.0 if i <= 4 else 0.0)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 55.0
	add_child(_camera)


func _build_particles() -> void:
	_process_mat = ShaderMaterial.new()
	_process_mat.shader = load("res://shaders/magneto_process.gdshader")
	_process_mat.set_shader_parameter("node_count", NODE_COUNT)

	_draw_mat = ShaderMaterial.new()
	_draw_mat.shader = load("res://shaders/magneto_draw.gdshader")
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _draw_mat

	var p := GPUParticles3D.new()
	p.amount = 30000
	p.lifetime = 8.0
	p.preprocess = 4.0
	p.fixed_fps = 60
	p.randomness = 0.5
	p.visibility_aabb = AABB(Vector3(-12, -12, -12), Vector3(24, 24, 24))
	p.process_material = _process_mat
	p.draw_pass_1 = quad
	_update_nodes(0.0)  # uniforms must exist before preprocess runs
	add_child(p)


func _build_audio() -> void:
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "Capture")
	var analyzer := AudioEffectSpectrumAnalyzer.new()
	analyzer.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
	AudioServer.add_bus_effect(idx, analyzer)
	# The analyzer sits before the bus fader, so it still sees the signal;
	# the fader keeps the captured audio from being played back (echo).
	AudioServer.set_bus_volume_db(idx, -80.0)
	_spectrum = AudioServer.get_bus_effect_instance(idx, 0)

	var player := AudioStreamPlayer.new()
	player.bus = "Capture"
	add_child(player)
	if _args.has("selftest"):
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = 44100.0
		player.stream = gen
		player.play()
		_test_gen = player.get_stream_playback()
	else:
		player.stream = AudioStreamMicrophone.new()
		player.play()
		_capturing = true


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0, 0.8))
	_hud.visible = false
	layer.add_child(_hud)
	add_child(layer)


func _process(delta: float) -> void:
	_t += delta
	if _test_gen:
		_feed_test_tone()
	if _capturing:
		_route_timer -= delta
		if _route_timer <= 0.0:
			_route_timer = ROUTE_CHECK_EVERY
			_route_to_spotify()
	_analyse(delta)
	_update_nodes(delta)
	_update_camera()

	var energy: float = (_levels.bass + _levels.mid + _levels.treble) / 3.0
	_process_mat.set_shader_parameter("bass", _levels.bass)
	_process_mat.set_shader_parameter("mid", _levels.mid)
	_process_mat.set_shader_parameter("treble", _levels.treble)
	_process_mat.set_shader_parameter("kick", _kick)
	_draw_mat.set_shader_parameter("energy", energy)

	if _hud.visible:
		_hud.text = "bass   %s\nmid    %s\ntreble %s\nkick   %s" % [
			_bar(_levels.bass), _bar(_levels.mid), _bar(_levels.treble), _bar(_kick)]
	_frame += 1
	_check_cli()


func _analyse(delta: float) -> void:
	var bands := {"bass": Vector2(30, 160), "mid": Vector2(160, 2000), "treble": Vector2(2000, 12000)}
	for b in bands:
		var m := _spectrum.get_magnitude_for_frequency_range(bands[b].x, bands[b].y)
		var db := linear_to_db(maxf((m.x + m.y) * 0.5, 1e-7))
		var raw := clampf((db + 70.0) / 60.0, 0.0, 1.0)
		# Auto gain: divide by a slowly-decaying peak so quiet and loud
		# tracks both use the whole range. Floor keeps silence silent.
		_peaks[b] = maxf(raw, maxf(_peaks[b] - delta * 0.05, 0.3))
		var v := clampf(raw / _peaks[b], 0.0, 1.0)
		v = v * v  # widen the gap between quiet and loud
		# Fast attack, slow release.
		var k := 18.0 if v > _levels[b] else 4.0
		_levels[b] = lerpf(_levels[b], v, 1.0 - exp(-k * delta))

	# Beat: bass jumps well above its recent average.
	_bass_avg = lerpf(_bass_avg, _levels.bass, 1.0 - exp(-1.5 * delta))
	_since_kick += delta
	if _levels.bass - _bass_avg > 0.12 and _since_kick > 0.22:
		_kick = 1.0
		_since_kick = 0.0
	_kick *= exp(-9.0 * delta)


func _route_to_spotify() -> void:
	# Wire Spotify's output ports straight into our capture ports and drop
	# any other input (the default mic WirePlumber hooks up at start), so
	# Discord or game audio never drives the particles.
	var out := []
	if OS.execute("pw-link", ["-l"], out) != 0:
		return
	var spotify: Array[String] = []
	var ours: Array[String] = []
	var feeds := {}  # our input port -> ports linked into it
	var port := ""
	for line: String in out[0].split("\n"):
		if line.is_empty():
			continue
		if not line.begins_with(" "):
			port = line.strip_edges()
			if port.begins_with(SPOTIFY_NODE + ":output_") and port not in spotify:
				spotify.append(port)
			elif port.begins_with(OUR_NODE + ":input_") and port not in ours:
				ours.append(port)
				feeds[port] = []
		elif "|<-" in line and feeds.has(port):
			feeds[port].append(line.split("|<-")[1].strip_edges())
	# Ports with no links are not in -l output; ask for ours explicitly.
	out.clear()
	OS.execute("pw-link", ["-i"], out)
	for line: String in out[0].split("\n"):
		var p := line.strip_edges()
		if p.begins_with(OUR_NODE + ":input_") and p not in ours:
			ours.append(p)
			feeds[p] = []
	out.clear()
	OS.execute("pw-link", ["-o"], out)
	for line: String in out[0].split("\n"):
		var p := line.strip_edges()
		if p.begins_with(SPOTIFY_NODE + ":output_") and p not in spotify:
			spotify.append(p)

	for dst: String in ours:
		for src: String in feeds[dst]:
			if src not in spotify:
				OS.execute("pw-link", ["-d", src, dst])
				print("unlink ", src, " -> ", dst)
		for src: String in spotify:
			if src not in feeds[dst]:
				OS.execute("pw-link", [src, dst])
				print("link ", src, " -> ", dst)


func _update_nodes(_delta: float) -> void:
	var pos := PackedVector3Array()
	var axes := PackedVector3Array()
	var hues := PackedVector3Array()
	var spread: float = 2.8 + _levels.bass * 0.6
	for i in NODE_COUNT:
		var f := float(i)
		var s := 0.11 + f * 0.023
		pos.append(Vector3(
			sin(_t * s * 1.3 + f * 1.7),
			sin(_t * s * 0.9 + f * 2.9) * 0.7,
			cos(_t * s * 1.1 + f * 0.6)) * spread)
		axes.append(Vector3(
			sin(_t * 0.07 + f * 2.1),
			cos(_t * 0.05 + f),
			sin(_t * 0.06 + f * 0.4)).normalized())
		# Palette drifts slowly so the scene changes colour over a song.
		var c: Color = PALETTE[i]
		c.h = fposmod(c.h + _t * 0.004, 1.0)
		hues.append(Vector3(c.r, c.g, c.b))
	_centroid = Vector3.ZERO
	for v in pos:
		_centroid += v / NODE_COUNT
	_process_mat.set_shader_parameter("nodes", pos)
	_process_mat.set_shader_parameter("axes", axes)
	_process_mat.set_shader_parameter("hues", hues)


func _update_camera() -> void:
	var a := _t * 0.05
	var r: float = 9.0 - _levels.bass * 0.4
	_camera.position = _centroid + Vector3(sin(a) * r, 1.5 + sin(_t * 0.07) * 1.2, cos(a) * r)
	_camera.look_at(_centroid)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F, KEY_F11:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		KEY_D:
			_hud.visible = not _hud.visible
		KEY_ESCAPE:
			get_tree().quit()


func _bar(v: float) -> String:
	var n := int(clampf(v, 0.0, 1.0) * 30.0)
	return "#".repeat(n) + ".".repeat(30 - n) + " %.2f" % v


# --- test hooks -------------------------------------------------------------

func _feed_test_tone() -> void:
	# 70 Hz sine pulsing twice a second: should light up bass and kick.
	var frames := _test_gen.get_frames_available()
	for i in frames:
		_test_phase += 70.0 / 44100.0
		var env := 1.0 if fmod(_test_phase / 70.0, 0.5) < 0.25 else 0.0
		var s := sin(_test_phase * TAU) * 0.5 * env
		_test_gen.push_frame(Vector2(s, s))


func _check_cli() -> void:
	var limit := int(_args.get("frames", "240"))
	if _args.has("selftest") or _args.has("meter"):
		if _frame % 30 == 0:
			print("frame %d  bass %.2f  mid %.2f  treble %.2f  kick %.2f" % [
				_frame, _levels.bass, _levels.mid, _levels.treble, _kick])
		if _frame >= limit:
			get_tree().quit()
	elif _args.has("shot") and _frame >= limit:
		get_viewport().get_texture().get_image().save_png(_args.shot)
		print("saved ", _args.shot)
		get_tree().quit()
