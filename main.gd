extends Node3D
## Magnetosphere-style visualizer. Everything is built in code so the scene
## file stays trivial. This script wires the parts together and owns the
## look: modes, particle materials, camera and background.
##   audio.gd   capture + analysis: bass / mid / treble, kick, presence
##   nodes.gd   the magnetic nodes: how many, where, their stars and bubbles
##   ui.gd      meters, announcements, right-click menu, keys
##   modes.gd   the visual modes; in Auto the mode changes with each song,
##              or the menu locks one (remembered across runs)
## Three particle systems (dots, thin trail lines, wide ribbons); each mode
## doses them. The music's overall loudness drives "presence": quiet
## passages show little more than the stars, loud ones fill out (like the
## original). Each mode change morphs over 6 s and is marked by a brief
## colour wash of the background, measured on the original video.
##
## CLI (after `--`): --shot=<png> [--frames=N]  save a frame and quit
##                   --mode=<index>             lock a mode for this run
##                   --nodes=<n>                fixed node count for this run
##                   --wash=<frames>            start a background wash this many
##                                              frames before the shot (peaks 1.5 s in)
##                   --selftest                 feed a test tone, print levels, quit
##                   --tone                     feed the test tone (shots without music)
##                   --meter                    print live capture levels, quit
##                   --dump=<csv>               log raw band dB every frame (tuning)

const Modes := preload("res://modes.gd")
const Audio := preload("res://audio.gd")
const Nodes := preload("res://nodes.gd")
const Ui := preload("res://ui.gd")

# Background wash on a mode change, after the original's 0:48-0:52: the
# colour rises for ~1.5 s while its hue slides (there red -> magenta ->
# deep blue), then fades back to black. Measured peak ~83/255 in sRGB.
const WASH_RISE := 1.5
const WASH_FALL := 0.8  # 1/s, exponential (ACES darkens the tail further)
const WASH_TIME := 4.5
const WASH_PEAK := 0.33
const WASH_SLIDE := -0.27  # hue turn over the rise
# Start hues: red to violet, so the wash stays in the original's family
# (full-saturation green or yellow read as a green screen).
const WASH_HUES := Vector2(0.8, 1.1)
# Seconds a mode change takes, on an S-curve (slow start, slow end).
# The old exponential ease moved 70 % in the first second: too abrupt
# (2026-10-10).
const MORPH_TIME := 6.0
# Global scale on everything beats and treble drive (blasts, flashes,
# camera punch, sparkle, jitter). 1.0 = the original wild version;
# 0.5 still read as too jumpy (2026-10-10).
const REACTIVITY := 0.35
# The camera follows beats through a low-pass (1/s), so a kick is a soft
# push in rather than a one-frame jolt (the jolt was the worst part).
const CAM_SMOOTH := 4.0
# In Auto, switch anyway after this long without a song change.
const FALLBACK_SWITCH := 300.0
const SETTINGS_PATH := "user://settings.cfg"

var _modes: Array = Modes.all()
var _audio: Audio
var _nodes: Nodes
var _ui: Ui
var _env: Environment
var _process_mat: ShaderMaterial
var _draw_mat: ShaderMaterial
var _lines_proc: ShaderMaterial
var _lines_draw: ShaderMaterial
var _rib_proc: ShaderMaterial
var _rib_draw: ShaderMaterial
var _dots: GPUParticles3D
var _lines: GPUParticles3D
var _ribbons: GPUParticles3D
var _group_mats := {}  # modes.gd group -> materials that receive it
var _uniforms := {}    # material -> names of the uniforms its shader has
var _camera: Camera3D
var _quitting := false

var _mode := 0
var _locked := -1  # -1 = auto
var _cur := {}     # live (blended) parameters, same shape as a _modes entry
var _from := {}    # _cur when the current morph started
var _morph := 1.0  # morph progress 0..1
var _since_switch := 0.0
var _first_track := true
# Background wash: seconds since it started, < 0 = none.
var _wash := -1.0
var _wash_hue := 0.0

var _t := 0.0
var _cam_phase := 0.0
var _cam_push := 0.0
var _turb_phase := 0.0

var _args := {}
var _frame := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	get_tree().auto_accept_quit = false  # window close goes through _quit()
	_load_settings()
	if _args.has("mode"):
		_locked = clampi(int(_args.mode), 0, _modes.size() - 1)
	_mode = maxi(_locked, 0)
	_cur = _modes[_mode].duplicate(true)

	_audio = Audio.new(_args.has("selftest") or _args.has("tone"), _args.get("dump", ""))
	_audio.track_changed.connect(_on_track_changed)
	add_child(_audio)

	_nodes = Nodes.new()
	if _args.has("nodes"):
		_nodes.fixed_count = clampi(int(_args.nodes), 0, Nodes.SLOTS)
	_nodes.start(_cur.scene)

	_build_environment()
	_build_camera()
	_build_particles()

	var names := []
	for m: Dictionary in _modes:
		names.append(m.name)
	_ui = Ui.new(names)
	_ui.locked = _locked
	_ui.lock_requested.connect(_set_lock)
	_ui.next_requested.connect(_on_next)
	_ui.quit_requested.connect(_quit)
	add_child(_ui)


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
	# Narrow lens: the scene fills ~1.8x more of the screen than at 55 deg
	# without the perspective distortion of moving the camera closer.
	_camera.fov = 32.0
	add_child(_camera)


func _build_particles() -> void:
	_process_mat = _shader_mat("res://shaders/magneto_process.gdshader")
	_draw_mat = _shader_mat("res://shaders/magneto_draw.gdshader")
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _draw_mat
	_dots = GPUParticles3D.new()
	# More than the 4-node version had: with up to 6 nodes and stray dust
	# each cluster would otherwise look thin.
	_dots.amount = 8000
	_dots.lifetime = 8.0
	_dots.preprocess = 4.0
	_dots.process_material = _process_mat
	_dots.draw_pass_1 = quad

	var tube := TubeTrailMesh.new()
	tube.radius = 0.006
	tube.radial_steps = 4
	tube.sections = 12
	tube.section_length = 0.1
	_lines_proc = _shader_mat("res://shaders/trail_process.gdshader")
	_lines_draw = _shader_mat("res://shaders/trail_draw.gdshader")
	_lines = _trail_system(tube, _lines_proc, _lines_draw, 900, 2.0, 0.7)

	var ribbon := RibbonTrailMesh.new()
	ribbon.shape = RibbonTrailMesh.SHAPE_FLAT
	ribbon.size = 0.3
	ribbon.sections = 12
	ribbon.section_length = 0.1
	_rib_proc = _shader_mat("res://shaders/trail_process.gdshader")
	_rib_draw = _shader_mat("res://shaders/trail_draw.gdshader")
	_rib_draw.set_shader_parameter("soft_edges", 1.0)
	_ribbons = _trail_system(ribbon, _rib_proc, _rib_draw, 220, 4.0, 1.2)

	for p: GPUParticles3D in [_dots, _lines, _ribbons]:
		p.fixed_fps = 60
		p.randomness = 0.5
		p.visibility_aabb = AABB(Vector3(-14, -14, -14), Vector3(28, 28, 28))
	_group_mats = {
		"dots_process": [_process_mat],
		"dots_draw": [_draw_mat],
		"lines": [_lines_proc, _lines_draw],
		"ribbons": [_rib_proc, _rib_draw],
	}

	# Uniforms must exist before preprocess runs.
	_blend_params(0.0)
	_update_nodes(0.0)
	for n: Node3D in [_dots, _lines, _ribbons, _nodes]:
		add_child(n)


func _shader_mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	var names := {}
	for u in m.shader.get_shader_uniform_list():
		names[u.name] = true
	_uniforms[m] = names
	return m


func _trail_system(mesh: PrimitiveMesh, proc: ShaderMaterial, draw: ShaderMaterial,
		amount: int, lifetime: float, trail_time: float) -> GPUParticles3D:
	mesh.material = draw
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.trail_enabled = true
	p.trail_lifetime = trail_time
	p.process_material = proc
	p.draw_pass_1 = mesh
	return p


## Set a uniform on every given material whose shader declares it.
func _set_param(mats: Array, uniform: String, value: Variant) -> void:
	for m: ShaderMaterial in mats:
		if _uniforms[m].has(uniform):
			m.set_shader_parameter(uniform, value)


func _process(delta: float) -> void:
	_t += delta
	_audio.update(delta)
	_update_wash(delta)

	_since_switch += delta
	if _locked < 0 and _since_switch > FALLBACK_SWITCH:
		_next_mode()

	_blend_params(delta)
	_update_nodes(delta)
	_update_camera(delta)

	var sc: Dictionary = _cur.scene
	var levels := _audio.levels
	var energy: float = (levels.bass + levels.mid + levels.treble) / 3.0
	_turb_phase += delta * sc.turb_speed * (1.0 + levels.mid)
	var kick := _audio.kick * REACTIVITY
	var treble: float = levels.treble * REACTIVITY
	var all_mats := [_process_mat, _draw_mat, _lines_proc, _lines_draw, _rib_proc, _rib_draw]
	_set_param(all_mats, "turb_phase", _turb_phase)
	_set_param(all_mats, "bass", levels.bass)
	_set_param(all_mats, "mid", levels.mid)
	_set_param(all_mats, "treble", treble)
	_set_param(all_mats, "kick", kick)
	_set_param(all_mats, "energy", energy)
	_set_param(all_mats, "presence", maxf(sc.breath_min, _audio.presence))
	_draw_mat.set_shader_parameter("sparkle_seed", int(_t * 12.0))
	# Systems a mode doesn't use stop simulating altogether.
	_dots.visible = _cur.dots_draw.amount > 0.01
	_lines.visible = _cur.lines.amount > 0.01
	_ribbons.visible = _cur.ribbons.amount > 0.01
	for p: GPUParticles3D in [_dots, _lines, _ribbons]:
		p.emitting = p.visible
	_env.glow_intensity = sc.glow * (1.0 + (levels.bass * 0.5 + kick) * sc.glow_pulse * 0.5)

	if _ui.meters_visible():
		var rows := [["bass", levels.bass], ["mid", levels.mid], ["treble", levels.treble],
			["kick", _audio.kick], ["presence", _audio.presence]]
		if _audio.capture_status() != "":
			rows.append(["capture", _audio.capture_status()])
		_ui.set_meters("%s  [%s]  nodes %d" % [
			_modes[_mode].name, "auto" if _locked < 0 else "locked", _nodes.count()], rows)
	_frame += 1
	_check_cli()


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
	_audio.stop()
	await get_tree().create_timer(0.25).timeout
	get_tree().quit()


# --- modes ------------------------------------------------------------------

func _blend_params(delta: float) -> void:
	# Morph from the snapshot taken at the mode change to the target mode;
	# delta 0 = snap (first frame).
	var target: Dictionary = _modes[_mode]
	_morph = 1.0 if delta == 0.0 else minf(_morph + delta / MORPH_TIME, 1.0)
	if _from.is_empty():
		_from = _cur.duplicate(true)
	var w := smoothstep(0.0, 1.0, _morph)
	for group: String in Modes.DEFAULTS:
		var cur: Dictionary = _cur[group]
		for key in cur:
			cur[key] = lerpf(_from[group][key], target[group][key], w)
		if _group_mats.has(group):
			for key in cur:
				_set_param(_group_mats[group], key, cur[key])
	for i in _cur.palette.size():
		_cur.palette[i] = _from.palette[i].lerp(target.palette[i], w)


func _set_mode(i: int) -> void:
	_since_switch = 0.0
	if i == _mode:
		return
	_mode = i
	# Start the morph from wherever we are (even mid-morph).
	_from = _cur.duplicate(true)
	_morph = 0.0
	# A scene change in the original: new node count, background wash.
	_nodes.pick_count(_modes[_mode].scene)
	_start_wash()


func _next_mode() -> void:
	# Random, but never the same one twice in a row.
	var n := _modes.size()
	_set_mode((_mode + 1 + randi() % (n - 1)) % n)


func _set_lock(i: int) -> void:
	_locked = i
	_ui.locked = i
	if i >= 0:
		_set_mode(i)
		_ui.show_toast("Locked: " + _modes[i].name)
	else:
		_ui.show_toast("Auto: changes with each song")
	_save_settings()


func _on_next() -> void:
	# Locked: move the lock along. Auto: just switch now.
	if _locked >= 0:
		_set_lock((_locked + 1) % _modes.size())
	else:
		_next_mode()
		_ui.show_toast(_modes[_mode].name)


func _on_track_changed(title: String, artist: String) -> void:
	if _locked < 0 and not _first_track:
		_next_mode()
	_first_track = false
	if title == "":
		return  # gap-detected song change: nothing to announce
	var lines := [title]
	if artist != "":
		lines.append(artist)
	_ui.show_toast("\n".join(lines))


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_locked = clampi(int(cfg.get_value("view", "locked", -1)), -1, _modes.size() - 1)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("view", "locked", _locked)
	cfg.save(SETTINGS_PATH)


# --- scene ------------------------------------------------------------------

func _update_nodes(delta: float) -> void:
	_nodes.update(delta, _t, _cur, _modes[_mode].scene, _audio, _audio.kick * REACTIVITY)
	var procs := [_process_mat, _lines_proc, _rib_proc]
	_set_param(procs, "weights", _nodes.weights)
	_set_param(procs, "nodes", _nodes.positions)
	_set_param(procs, "centroid", _nodes.centroid)
	_set_param(procs, "axes", _nodes.axes)
	_set_param(procs, "hues", _nodes.hues)
	# Black-hole gravity (mode 7): the dots feel each ball and its size.
	_process_mat.set_shader_parameter("moons", _nodes.moons)
	_process_mat.set_shader_parameter("moon_r", _nodes.moon_r)


func _start_wash() -> void:
	_wash = 0.0
	_wash_hue = randf_range(WASH_HUES.x, WASH_HUES.y)


func _update_wash(delta: float) -> void:
	if _wash < 0.0:
		return
	_wash += delta
	if _wash >= WASH_TIME:
		_wash = -1.0
		_env.background_color = Color.BLACK
		return
	var rise := smoothstep(0.0, WASH_RISE, _wash)
	var v := rise * exp(-maxf(_wash - WASH_RISE, 0.0) * WASH_FALL)
	var h := fposmod(_wash_hue + WASH_SLIDE * rise, 1.0)
	_env.background_color = Color.from_hsv(h, 1.0, WASH_PEAK * v)


func _update_camera(delta: float) -> void:
	var sc: Dictionary = _cur.scene
	var centroid := _nodes.centroid
	_cam_phase += delta * sc.cam_speed
	_cam_push = lerpf(_cam_push, _audio.kick * REACTIVITY * sc.cam_punch, 1.0 - exp(-CAM_SMOOTH * delta))
	var r: float = sc.cam_dist - _audio.levels.bass * 0.4 - _cam_push
	_camera.position = centroid + Vector3(sin(_cam_phase) * r, 1.5 + sin(_t * 0.07) * 1.2, cos(_cam_phase) * r)
	_camera.look_at(centroid)
	_draw_mat.set_shader_parameter("focus_dist", _camera.position.distance_to(centroid))


# --- test hooks -------------------------------------------------------------

func _check_cli() -> void:
	var limit := int(_args.get("frames", "240"))
	if _args.has("wash") and _frame == limit - int(_args.wash):
		_start_wash()
	if _args.has("selftest") or _args.has("meter"):
		if _frame % 30 == 0:
			var levels := _audio.levels
			print("t %5.1f  frame %d  bass %.2f  mid %.2f  treble %.2f  kicks %d  presence %.2f  fps %d" % [
				_t, _frame, levels.bass, levels.mid, levels.treble, _audio.kick_count, _audio.presence,
				Engine.get_frames_per_second()])
			_audio.kick_count = 0
		if _frame >= limit:
			_quit()
	elif _args.has("shot") and _frame >= limit and not _quitting:
		get_viewport().get_texture().get_image().save_png(_args.shot)
		print("saved ", _args.shot)
		_quit()
