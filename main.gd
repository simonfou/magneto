extends Node3D
## Magnetosphere-style visualizer. Everything is built in code so the scene
## file stays trivial. Audio comes straight from whatever Spotify is
## playing (see spotify.gd), analysed into bass / mid / treble / kick.
## Visual modes live in modes.gd; in Auto the mode changes with each song,
## or the right-click menu locks one (remembered across runs).
##
## Keys: right-click = menu, 1-5 = lock a mode, 0 or A = auto, N = next,
##       F / F11 = fullscreen, D = level meters, Esc = quit.
## CLI (after `--`): --shot=<png> [--frames=N]  save a frame and quit
##                   --mode=<index>             lock a mode for this run
##                   --selftest                 feed a test tone, print levels, quit
##                   --meter                    print live capture levels, quit
##                   --dump=<csv>               log raw band dB every frame (tuning)

const Modes := preload("res://modes.gd")
const Spotify := preload("res://spotify.gd")

const NODE_COUNT := 4
# How fast parameters morph toward a new mode (1/s): ~3 s to settle.
const BLEND_RATE := 1.2
# Global scale on everything beats and treble drive (blasts, flashes,
# camera punch, sparkle, jitter). 1.0 = the original wild version.
const REACTIVITY := 0.5
# In Auto, switch anyway after this long without a song change.
const FALLBACK_SWITCH := 300.0
# Below this a band counts as silence (no music, or before Spotify is wired).
const SILENCE_DB := -100.0
const SETTINGS_PATH := "user://settings.cfg"
const MENU_AUTO := 100
const MENU_NEXT := 200
const MENU_FULLSCREEN := 201
const MENU_METERS := 202
const MENU_QUIT := 203

var _env: Environment
var _process_mat: ShaderMaterial
var _draw_mat: ShaderMaterial
var _camera: Camera3D
var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _spotify: Spotify
var _player: AudioStreamPlayer
var _quitting := false
var _hud: Label
var _toast: Label
var _toast_tween: Tween
var _menu: PopupMenu

var _mode := 0
var _locked := -1  # -1 = auto
var _cur := {}     # live (blended) parameters, same shape as a Modes.LIST entry
var _since_switch := 0.0
var _first_track := true

var _t := 0.0
var _node_phase := 0.0
var _cam_phase := 0.0
var _hue_phase := 0.0
var _turb_phase := 0.0
var _levels := {"bass": 0.0, "mid": 0.0, "treble": 0.0}
# Per-band calibration in dB: a ceiling that sinks and a floor that rises
# slowly, so each band uses its full 0..1 range whatever the track/volume.
var _hi := {"bass": -200.0, "mid": -200.0, "treble": -200.0}
var _lo := {"bass": 0.0, "mid": 0.0, "treble": 0.0}
var _bass_fast := -200.0
var _bass_slow := -200.0
var _rise_avg := 1.0
var _kick := 0.0
var _since_kick := 1.0
var _kick_count := 0
var _centroid := Vector3.ZERO

var _args := {}
var _frame := 0
var _test_gen: AudioStreamGeneratorPlayback
var _test_phase := 0.0
var _dump: FileAccess


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	get_tree().auto_accept_quit = false  # window close goes through _quit()
	_load_settings()
	if _args.has("dump"):
		_dump = FileAccess.open(_args.dump, FileAccess.WRITE)
	if _args.has("mode"):
		_locked = clampi(int(_args.mode), 0, Modes.LIST.size() - 1)
	_mode = maxi(_locked, 0)
	_cur = Modes.LIST[_mode].duplicate(true)

	_build_environment()
	_build_camera()
	_build_particles()
	_build_audio()
	_build_ui()


func _build_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color.BLACK
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.glow_enabled = true
	_env.glow_bloom = 0.0
	_env.glow_hdr_threshold = 1.0
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in range(1, 7):
		_env.set_glow_level(i, 1.0 if i <= 4 else 0.0)
	var we := WorldEnvironment.new()
	we.environment = _env
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
	p.visibility_aabb = AABB(Vector3(-14, -14, -14), Vector3(28, 28, 28))
	p.process_material = _process_mat
	p.draw_pass_1 = quad
	# Uniforms must exist before preprocess runs.
	_blend_params(0.0)
	_update_nodes(0.0)
	add_child(p)


func _build_audio() -> void:
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
	_spotify.track_changed.connect(_on_track_changed)
	add_child(_spotify)

	_player = AudioStreamPlayer.new()
	var player := _player
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
		_spotify.capture_enabled = true


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0, 0.8))
	_hud.visible = false
	layer.add_child(_hud)

	# Song / mode announcements, bottom-left like the iTunes one.
	_toast = Label.new()
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_left = 40
	_toast.offset_top = -240
	_toast.offset_bottom = -40
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_toast.add_theme_font_size_override("font_size", 26)
	_toast.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.modulate.a = 0.0
	layer.add_child(_toast)

	_menu = PopupMenu.new()
	_menu.add_radio_check_item("Auto: change with each song   (0)", MENU_AUTO)
	_menu.add_separator("Lock on")
	for i in Modes.LIST.size():
		_menu.add_radio_check_item("%s   (%d)" % [Modes.LIST[i].name, i + 1], i)
	_menu.add_separator()
	_menu.add_item("Next mode   (N)", MENU_NEXT)
	_menu.add_item("Fullscreen   (F)", MENU_FULLSCREEN)
	_menu.add_item("Level meters   (D)", MENU_METERS)
	_menu.add_item("Quit   (Esc)", MENU_QUIT)
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)


func _process(delta: float) -> void:
	_t += delta
	if _test_gen:
		_feed_test_tone()
	_analyse(delta)

	_since_switch += delta
	if _locked < 0 and _since_switch > FALLBACK_SWITCH:
		_next_mode()

	_blend_params(delta)
	_update_nodes(delta)
	_update_camera(delta)

	var sc: Dictionary = _cur.scene
	var energy: float = (_levels.bass + _levels.mid + _levels.treble) / 3.0
	_turb_phase += delta * sc.turb_speed * (1.0 + _levels.mid)
	_process_mat.set_shader_parameter("turb_phase", _turb_phase)
	_process_mat.set_shader_parameter("bass", _levels.bass)
	_process_mat.set_shader_parameter("mid", _levels.mid)
	var kick := _kick * REACTIVITY
	var treble: float = _levels.treble * REACTIVITY
	_process_mat.set_shader_parameter("treble", treble)
	_process_mat.set_shader_parameter("kick", kick)
	_draw_mat.set_shader_parameter("energy", energy)
	_draw_mat.set_shader_parameter("kick", kick)
	_draw_mat.set_shader_parameter("treble", treble)
	_draw_mat.set_shader_parameter("sparkle_seed", int(_t * 12.0))
	_env.glow_intensity = sc.glow * (1.0 + (_levels.bass * 0.5 + kick) * sc.glow_pulse * 0.5)

	if _hud.visible:
		_hud.text = "%s  [%s]\nbass   %s\nmid    %s\ntreble %s\nkick   %s" % [
			Modes.LIST[_mode].name, "auto" if _locked < 0 else "locked",
			_bar(_levels.bass), _bar(_levels.mid), _bar(_levels.treble), _bar(_kick)]
	_frame += 1
	_check_cli()


func _analyse(delta: float) -> void:
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
			_levels[b] = lerpf(_levels[b], 0.0, 1.0 - exp(-6.0 * delta))
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
		var k := 15.0 if v > _levels[b] else 4.0
		_levels[b] = lerpf(_levels[b], v, 1.0 - exp(-k * delta))

	# Beat: the bass envelope jumps above its recent level by more than it
	# usually does for this track. Thresholds tuned offline on --dump data
	# (~1.7 beats/s on metal; the analyzer only updates ~21 times/s).
	_since_kick += delta
	if bass_db < SILENCE_DB:
		_bass_fast = bass_db
		_bass_slow = bass_db
		_kick *= exp(-7.0 * delta)
		return
	if _bass_slow < SILENCE_DB:  # music just started: no fake beat
		_bass_slow = bass_db
		_bass_fast = bass_db
	_bass_fast = lerpf(_bass_fast, bass_db, 1.0 - exp(-60.0 * delta))
	_bass_slow = lerpf(_bass_slow, bass_db, 1.0 - exp(-4.0 * delta))
	var rise := _bass_fast - _bass_slow
	_rise_avg = clampf(lerpf(_rise_avg, absf(rise), 1.0 - exp(-0.5 * delta)), 0.5, 4.0)
	if rise > maxf(1.5, _rise_avg * 1.2) and _since_kick > 0.14:
		_kick = 1.0
		_since_kick = 0.0
		_kick_count += 1
	_kick *= exp(-7.0 * delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()


func _quit() -> void:
	if _quitting:
		return
	_quitting = true
	# Stop the mic stream and give the audio server time to drop it;
	# quitting straight away leaks it (Godot warns at exit). Two frames
	# were not always enough (2 leaks in 5 runs); 0.25 s was 0 in 10.
	_player.stop()
	_player.stream = null
	await get_tree().create_timer(0.25).timeout
	get_tree().quit()


# --- modes ------------------------------------------------------------------

func _blend_params(delta: float) -> void:
	# delta 0 = snap (first frame); otherwise ease toward the target mode.
	var target: Dictionary = Modes.LIST[_mode]
	var w := 1.0 if delta == 0.0 else 1.0 - exp(-BLEND_RATE * delta)
	for group in ["process", "draw", "scene"]:
		var cur: Dictionary = _cur[group]
		for key in cur:
			cur[key] = lerpf(cur[key], target[group][key], w)
	for i in _cur.palette.size():
		_cur.palette[i] = _cur.palette[i].lerp(target.palette[i], w)
	for key in _cur.process:
		_process_mat.set_shader_parameter(key, _cur.process[key])
	for key in _cur.draw:
		_draw_mat.set_shader_parameter(key, _cur.draw[key])


func _set_mode(i: int) -> void:
	_mode = i
	_since_switch = 0.0


func _next_mode() -> void:
	# Random, but never the same one twice in a row.
	var n := Modes.LIST.size()
	_set_mode((_mode + 1 + randi() % (n - 1)) % n)


func _set_lock(i: int) -> void:
	_locked = i
	if i >= 0:
		_set_mode(i)
		_show_toast("Locked: " + Modes.LIST[i].name)
	else:
		_show_toast("Auto: changes with each song")
	_save_settings()


func _on_track_changed(title: String, artist: String) -> void:
	if _locked < 0 and not _first_track:
		_next_mode()
	_first_track = false
	var lines := [title]
	if artist != "":
		lines.append(artist)
	_show_toast("\n".join(lines))


func _show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.5)
	_toast_tween.tween_interval(4.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 2.0)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_locked = clampi(int(cfg.get_value("view", "locked", -1)), -1, Modes.LIST.size() - 1)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("view", "locked", _locked)
	cfg.save(SETTINGS_PATH)


# --- scene motion -----------------------------------------------------------

func _update_nodes(delta: float) -> void:
	var sc: Dictionary = _cur.scene
	_node_phase += delta * sc.node_speed
	_hue_phase += delta * sc.hue_speed
	var pos := PackedVector3Array()
	var axes := PackedVector3Array()
	var hues := PackedVector3Array()
	var spread: float = sc.spread * (1.0 + _levels.bass * 0.2)
	# Shared axis that "align" pulls every node toward (disks in Galaxy).
	var common := Vector3(sin(_t * 0.03) * 0.3, 1.0, cos(_t * 0.02) * 0.3).normalized()
	for i in NODE_COUNT:
		var f := float(i)
		var s := 0.11 + f * 0.023
		pos.append(Vector3(
			sin(_node_phase * s * 1.3 + f * 1.7),
			sin(_node_phase * s * 0.9 + f * 2.9) * 0.7,
			cos(_node_phase * s * 1.1 + f * 0.6)) * spread)
		var own := Vector3(
			sin(_t * 0.07 + f * 2.1),
			cos(_t * 0.05 + f),
			sin(_t * 0.06 + f * 0.4)).normalized()
		axes.append(own.slerp(common, sc.axis_align).normalized())
		# Palette drifts slowly so the scene changes colour over a song.
		var c: Color = _cur.palette[i]
		c.h = fposmod(c.h + _hue_phase, 1.0)
		hues.append(Vector3(c.r, c.g, c.b))
	_centroid = Vector3.ZERO
	for v in pos:
		_centroid += v / NODE_COUNT
	_process_mat.set_shader_parameter("nodes", pos)
	_process_mat.set_shader_parameter("centroid", _centroid)
	_process_mat.set_shader_parameter("axes", axes)
	_process_mat.set_shader_parameter("hues", hues)


func _update_camera(delta: float) -> void:
	var sc: Dictionary = _cur.scene
	_cam_phase += delta * sc.cam_speed
	var r: float = sc.cam_dist - _levels.bass * 0.4 - _kick * REACTIVITY * sc.cam_punch
	_camera.position = _centroid + Vector3(sin(_cam_phase) * r, 1.5 + sin(_t * 0.07) * 1.2, cos(_cam_phase) * r)
	_camera.look_at(_centroid)
	_draw_mat.set_shader_parameter("focus_dist", _camera.position.distance_to(_centroid))


# --- input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_open_menu(event.position)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: Key = event.keycode
	if key >= KEY_1 and key < KEY_1 + Modes.LIST.size():
		_set_lock(key - KEY_1)
		return
	match key:
		KEY_0, KEY_A:
			_set_lock(-1)
		KEY_N:
			_on_menu(MENU_NEXT)
		KEY_F, KEY_F11:
			_on_menu(MENU_FULLSCREEN)
		KEY_D:
			_on_menu(MENU_METERS)
		KEY_ESCAPE:
			_on_menu(MENU_QUIT)


func _open_menu(at: Vector2) -> void:
	for idx in _menu.item_count:
		var id := _menu.get_item_id(idx)
		if id == MENU_AUTO:
			_menu.set_item_checked(idx, _locked < 0)
		elif id >= 0 and id < Modes.LIST.size():
			_menu.set_item_checked(idx, id == _locked)
	_menu.position = Vector2i(at)
	_menu.popup()


func _on_menu(id: int) -> void:
	match id:
		MENU_AUTO:
			_set_lock(-1)
		MENU_NEXT:
			# Locked: move the lock along. Auto: just switch now.
			if _locked >= 0:
				_set_lock((_locked + 1) % Modes.LIST.size())
			else:
				_next_mode()
				_show_toast(Modes.LIST[_mode].name)
		MENU_FULLSCREEN:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		MENU_METERS:
			_hud.visible = not _hud.visible
		MENU_QUIT:
			_quit()
		_:
			if id >= 0 and id < Modes.LIST.size():
				_set_lock(id)


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
			print("t %5.1f  frame %d  bass %.2f  mid %.2f  treble %.2f  kicks %d" % [
				_t, _frame, _levels.bass, _levels.mid, _levels.treble, _kick_count])
			_kick_count = 0
		if _frame >= limit:
			_quit()
	elif _args.has("shot") and _frame >= limit and not _quitting:
		get_viewport().get_texture().get_image().save_png(_args.shot)
		print("saved ", _args.shot)
		_quit()
