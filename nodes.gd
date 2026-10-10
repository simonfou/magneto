extends Node3D
## The magnetic nodes the particles gather around. Up to SLOTS of them roam
## the scene, each with a white star and an optional black bubble or moon.
## How many show varies like in the original (measured on the video: 4-5,
## 1, 2, 3-4, 0, 1-3, 5-4): a new count every 8-25 s within the mode's
## nodes_min/nodes_max, landing on a beat, or a short rest with none. Each
## node fades in and out by its weight.
##
## update() moves everything and leaves what the particle shaders need in
## positions / axes / hues / weights / centroid / moons / moon_r; main.gd
## pushes it to the materials.

const Audio := preload("res://audio.gd")

const SLOTS := 6
# Seconds for a node to fade fully in or out.
const NODE_FADE := 1.2
# How long a node count holds before the next one (seconds, random).
const COUNT_HOLD := Vector2(8.0, 25.0)
# Chance that the next count is a rest with no node at all, held briefly:
# only drifting dust, as in the original around 0:46-0:56.
const REST_CHANCE := 0.08
const REST_HOLD := Vector2(4.0, 8.0)
# Nodes roam wider horizontally than vertically, so the scene fills a
# 16:9 screen instead of sitting in a round blob in the middle.
const WIDE := 1.35

var fixed_count := -1  # --nodes
var positions := PackedVector3Array()
var axes := PackedVector3Array()
var hues := PackedVector3Array()
var weights := PackedFloat32Array()  # 0..1, eased
var centroid := Vector3.ZERO
var moons := PackedVector3Array()    # black balls (Black holes mode)
var moon_r := 0.0

var _alive: Array[bool] = []
var _count_timer := 0.0
var _node_phase := 0.0
var _hue_phase := 0.0
var _stars: Array[MeshInstance3D] = []
var _bubbles: Array[MeshInstance3D] = []
var _star_mats: Array[ShaderMaterial] = []
var _star_occluded: Array[ShaderMaterial] = []


func _init() -> void:
	_alive.resize(SLOTS)
	weights.resize(SLOTS)
	var star_mesh := QuadMesh.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = 48
	sphere.rings = 24
	for i in SLOTS:
		var star := MeshInstance3D.new()
		star.mesh = star_mesh
		_star_mats.append(_mat("res://shaders/star.gdshader"))
		_star_occluded.append(_mat("res://shaders/star_occluded.gdshader"))
		star.material_override = _star_mats[i]
		_stars.append(star)
		var bubble := MeshInstance3D.new()
		bubble.mesh = sphere
		bubble.material_override = _mat("res://shaders/bubble.gdshader")
		bubble.visible = false
		_bubbles.append(bubble)
	for n: Node3D in _bubbles + _stars:
		add_child(n)


func _mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m


func count() -> int:
	return _alive.count(true)


## First count, shown at once (no fade in).
func start(scene: Dictionary) -> void:
	pick_count(scene)
	for i in SLOTS:
		weights[i] = 1.0 if _alive[i] else 0.0


## Choose how many nodes show next (within the mode's range, or a rare
## rest with none) and switch random slots on or off to match.
func pick_count(scene: Dictionary) -> void:
	var have := count()
	var n := fixed_count
	if n < 0:
		if randf() < REST_CHANCE and have > 0:
			n = 0
		else:
			var lo := int(scene.nodes_min)
			var hi := int(scene.nodes_max)
			n = randi_range(lo, hi)
			if n == have and hi > lo:  # always a visible change
				n = lo + (n - lo + 1 + randi() % (hi - lo)) % (hi - lo + 1)
	var on: Array[int] = []
	var off: Array[int] = []
	for i in SLOTS:
		if _alive[i]:
			on.append(i)
		else:
			off.append(i)
	on.shuffle()
	off.shuffle()
	while on.size() > n:
		_alive[on.pop_back()] = false
	while on.size() < n:
		var i: int = off.pop_back()
		_alive[i] = true
		on.append(i)
	var hold := REST_HOLD if n == 0 else COUNT_HOLD
	_count_timer = randf_range(hold.x, hold.y)


## cur: the live (blended) mode; target_scene: where it is heading, whose
## node range new counts use. kick is already scaled by main.gd.
func update(delta: float, t: float, cur: Dictionary, target_scene: Dictionary, audio: Audio,
		kick: float) -> void:
	_count_timer -= delta
	# Once due, wait for a beat so the change lands on the music (or give up
	# waiting after 3 s).
	if _count_timer <= 0.0 and (audio.since_kick == 0.0 or _count_timer < -3.0):
		pick_count(target_scene)
	for i in SLOTS:
		weights[i] = move_toward(weights[i], 1.0 if _alive[i] else 0.0, delta / NODE_FADE)

	var sc: Dictionary = cur.scene
	var bass: float = audio.levels.bass
	_node_phase += delta * sc.node_speed
	_hue_phase += delta * sc.hue_speed
	positions.clear()
	axes.clear()
	hues.clear()
	# The scene gathers in on quiet passages and opens up on loud ones.
	var spread: float = sc.spread * (0.65 + 0.35 * audio.presence) * (1.0 + bass * 0.2)
	# Shared axis that "align" pulls every node toward (disks in Galaxy).
	var common := Vector3(sin(t * 0.03) * 0.3, 1.0, cos(t * 0.02) * 0.3).normalized()
	for i in SLOTS:
		var f := float(i)
		var s := 0.11 + f * 0.023
		positions.append(Vector3(
			sin(_node_phase * s * 1.3 + f * 1.7) * WIDE,
			sin(_node_phase * s * 0.9 + f * 2.9) * 0.45,
			cos(_node_phase * s * 1.1 + f * 0.6) * WIDE) * spread)
		var own := Vector3(
			sin(t * 0.07 + f * 2.1),
			cos(t * 0.05 + f),
			sin(t * 0.06 + f * 0.4)).normalized()
		axes.append(own.slerp(common, sc.axis_align).normalized())
		# Palette drifts slowly so the scene changes colour over a song; slots
		# past the palette reuse it with a hue offset.
		var pal: Array = cur.palette
		var c: Color = pal[i % pal.size()]
		c.h = fposmod(c.h + _hue_phase + (0.08 if i >= pal.size() else 0.0), 1.0)
		hues.append(Vector3(c.r, c.g, c.b))
	# Centre of the live nodes (all of them, a little, so it is defined
	# with none alive), eased so the camera pans rather than jumps when
	# nodes come and go.
	var sum := Vector3.ZERO
	var total := 0.0
	for i in SLOTS:
		var w := weights[i] + 0.02
		sum += positions[i] * w
		total += w
	var target := sum / total
	centroid = target if delta == 0.0 else centroid.lerp(target, 1.0 - exp(-1.5 * delta))

	var dp: Dictionary = cur.dots_process
	# Bubbles track the dots' shell so the dots sit on their surface.
	var inflate: float = 1.0 + bass * dp.bass_shell + kick * dp.kick_shell
	moon_r = (dp.shell_min + dp.shell_max) * 0.5 * inflate * sc.bubble_scale * sc.bubble
	var star_s: float = sc.star_size * (1.0 + bass * 0.15 + kick * 0.2)
	moons.clear()
	for i in SLOTS:
		var hue := Color(hues[i].x, hues[i].y, hues[i].z)
		var w := weights[i]
		_stars[i].visible = w > 0.001
		_stars[i].position = positions[i]
		_stars[i].scale = Vector3.ONE * maxf(star_s * w, 0.001)
		var tint := Color.WHITE.lerp(hue, 0.15)
		for sm: ShaderMaterial in [_star_mats[i], _star_occluded[i]]:
			sm.set_shader_parameter("glow", sc.star_glow)
			sm.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
		_bubbles[i].visible = moon_r * w > 0.02
		# moon_dist > 0: the ball orbits beside its star instead of around it.
		var ma := t * 0.15 + float(i) * 1.7
		var moon_off: Vector3 = Vector3(cos(ma), sin(ma * 0.7) * 0.4, sin(ma)) * sc.moon_dist
		_bubbles[i].position = positions[i] + moon_off
		moons.append(positions[i] + moon_off)
		_bubbles[i].scale = Vector3.ONE * maxf(moon_r * w, 0.001)
		var bm: ShaderMaterial = _bubbles[i].material_override
		bm.set_shader_parameter("rim_color", hues[i])
		bm.set_shader_parameter("glass", sc.bubble_glass)
		bm.set_shader_parameter("lit", sc.moon_lit)
		bm.set_shader_parameter("light_pos", positions[i])
		bm.set_shader_parameter("light_color", Vector3(tint.r, tint.g, tint.b))
		# Black balls hide the star inside them; elsewhere stars shine through.
		_stars[i].material_override = _star_occluded[i] if sc.star_occlude > 0.5 else _star_mats[i]
