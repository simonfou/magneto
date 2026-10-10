// Particle physics: a velocity field built from a handful of moving
// "magnetic" nodes. Particles settle on a shell around their home node,
// orbit its axis and ride a turbulent flow; they steer toward the field rather than
// accelerate, so the cloud stays stable. Every knob is a uniform so the
// modes in modes.gd can reshape it; audio uniforms come from main.gd.
shader_type particles;

const int MAX_NODES = 6;

uniform int node_count = 4;
uniform vec3 nodes[MAX_NODES];
uniform vec3 axes[MAX_NODES];
uniform vec3 hues[MAX_NODES];

uniform float attraction = 2.0;
uniform float swirl = 2.4;
uniform float drag = 2.5;
uniform float max_speed = 4.0;
uniform float falloff = 1.5;     // how fast a node's influence fades with distance
uniform float shell_min = 0.6;
uniform float shell_max = 1.1;
uniform float flatten = 0.0;     // squash shells into disks around each axis
uniform float turbulence = 0.15;
uniform float turb_scale = 0.8;
uniform float turb_phase = 0.0;  // integrated in main.gd
uniform float spawn_radius = 1.6;
uniform vec3 centroid = vec3(0.0);  // centre of the nodes, from main.gd
uniform float bound = 3.5;           // fence radius around the centroid
uniform float dust = 0.0;            // share of particles thrown far out as dust
uniform float dust_spread = 3.0;     // how much further out the dust sits
uniform vec3 moons[MAX_NODES];       // black balls (mode 7), from main.gd
uniform float moon_r = 0.0;          // their radius
uniform float moon_pull = 0.0;       // their gravity: spiral in, vanish inside

// Audio, all roughly 0..1, and how hard each one hits.
uniform float bass = 0.0;
uniform float mid = 0.0;
uniform float treble = 0.0;
uniform float kick = 0.0;  // spikes on a bass onset, decays in main.gd
uniform float kick_push = 7.0;
uniform float kick_shell = 0.7;
uniform float bass_shell = 0.5;
uniform float mid_swirl = 1.5;
uniform float mid_turb = 0.5;
uniform float treble_jitter = 0.6;

#include "res://shaders/common.gdshaderinc"

// Each particle belongs to one "home" node for its whole life: that node
// holds it like a spring, so the scene reads as separate glowing clusters
// with empty space between them, as in the original.
int home_of(uint index) {
	return int(hash(index * 2246822519u + 3u) * float(node_count)) % node_count;
}

void start() {
	uint seed = INDEX * 7919u + RANDOM_SEED * 104729u + uint(NUMBER) * 31u;
	int k = home_of(INDEX);
	vec3 dir = random_unit(seed + 11u);

	if (RESTART_POSITION) {
		TRANSFORM = mat4(1.0);
		TRANSFORM[3].xyz = nodes[k] + dir * spawn_radius * (0.3 + 0.7 * hash(seed + 5u));
	}
	if (RESTART_VELOCITY) {
		// Start on a rough orbit: tangent to the node's axis.
		vec3 t = cross(axes[k], dir);
		VELOCITY = normalize(t + 0.2 * random_unit(seed + 23u)) * (1.0 + hash(seed + 29u));
	}
	// The home node's hue, with a few hot white sparks.
	vec3 c = hues[k];
	if (hash(seed + 41u) < 0.06) {
		c = vec3(1.0, 0.95, 0.85);
	}
	COLOR = vec4(c, 0.0);
	CUSTOM = vec4(VELOCITY, 0.0);
}

void process() {
	vec3 p = TRANSFORM[3].xyz;
	int home = home_of(INDEX);
	// Each particle settles on its own shell radius; bass and beats inflate it.
	float shell = mix(shell_min, shell_max, hash(INDEX * 2654435761u + 7u));
	shell *= 1.0 + bass * bass_shell + kick * kick_shell;
	if (hash(INDEX * 1597334677u + 99u) < dust) {
		shell *= dust_spread;
	}
	vec3 flow = vec3(0.0);

	// Home node: spring onto the shell (no falloff, so it never escapes),
	// orbit around the axis, optional squash into a disk.
	vec3 d = nodes[home] - p;
	float r = length(d) + 1e-3;
	vec3 n = d / r;
	flow += n * (r - shell) * attraction;
	flow += cross(axes[home], n) * swirl * (1.0 + mid * mid_swirl) / (1.0 + r * r * falloff * 0.3);
	flow += axes[home] * dot(d, axes[home]) * flatten;
	// Other nodes only bend the orbit a little, where clusters pass close.
	for (int i = 0; i < node_count; i++) {
		if (i == home) {
			continue;
		}
		vec3 di = nodes[i] - p;
		float ri = length(di) + 1e-3;
		float f = 1.0 / (1.0 + ri * ri * falloff);
		flow += cross(axes[i], di / ri) * swirl * 0.3 * f;
	}
	// Black holes: pull nearby dots in and spin them around; once inside
	// the opaque ball they are hidden, so the hole seems to swallow them.
	if (moon_pull > 0.0 && moon_r > 0.01) {
		for (int i = 0; i < node_count; i++) {
			vec3 dm = moons[i] - p;
			float rm = length(dm) + 1e-3;
			float reach = moon_r * 3.0;
			if (rm < reach) {
				float g = moon_pull * (1.0 - rm / reach) * (moon_r / rm);
				flow += dm / rm * g * 2.0;
				flow += cross(axes[i], dm / rm) * g * 1.5;
			}
		}
	}
	flow += flow_noise(p * turb_scale, turb_phase) * turbulence * (1.0 + mid * mid_turb);
	// Treble: jitter so the cloud shimmers.
	uint seed = INDEX * 9973u + uint(TIME * 30.0) * 131u;
	flow += random_unit(seed) * treble * treble_jitter;
	// Beat: blast away from the home node (the spring brings it back).
	flow -= n * kick * kick_push;
	// Invisible fence around the whole scene so it never fills the window.
	vec3 off = p - centroid;
	float dist = length(off);
	if (dist > bound) {
		flow -= off / dist * (dist - bound) * 3.0;
	}

	// Steer toward the flow; drag sets how tightly particles follow it.
	VELOCITY = mix(VELOCITY, flow, 1.0 - exp(-drag * DELTA));
	float sp = length(VELOCITY);
	float cap = max_speed * (1.0 + bass * 0.5 + kick);
	if (sp > cap) {
		VELOCITY *= cap / sp;
	}

	// Age 0..1 over the particle's life, for fade in/out in the draw pass.
	CUSTOM.w += DELTA / LIFETIME;
	CUSTOM.xyz = VELOCITY;
	float age = CUSTOM.w;
	COLOR.a = smoothstep(0.0, 0.1, age) * (1.0 - smoothstep(0.75, 1.0, age));
}
