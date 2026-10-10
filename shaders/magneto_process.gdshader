// Particle physics: a velocity field built from a handful of moving
// "magnetic" nodes. Particles settle on shells around each node, orbit its
// axis and ride a turbulent flow; they steer toward the field rather than
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

float hash(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return float(x) / 4294967295.0;
}

vec3 random_unit(uint seed) {
	float z = hash(seed) * 2.0 - 1.0;
	float a = hash(seed + 1u) * TAU;
	float r = sqrt(1.0 - z * z);
	return vec3(r * cos(a), r * sin(a), z);
}

// Cheap swirly flow: each component depends on the other axes, which
// gives long ribbon-like streams rather than random noise.
vec3 flow_noise(vec3 p, float t) {
	return vec3(
		sin(p.y * 1.3 + t) + cos(p.z * 1.7 - t * 0.7),
		sin(p.z * 1.1 - t * 0.8) + cos(p.x * 1.5 + t * 0.6),
		sin(p.x * 1.2 + t * 0.9) + cos(p.y * 1.4 - t * 0.5)) * 0.5;
}

void start() {
	uint seed = INDEX * 7919u + RANDOM_SEED * 104729u + uint(NUMBER) * 31u;
	int k = int(hash(seed) * float(node_count)) % node_count;
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
	// Mostly the node's hue, with a few hot white sparks.
	vec3 c = hues[k];
	if (hash(seed + 41u) < 0.06) {
		c = vec3(1.0, 0.95, 0.85);
	}
	COLOR = vec4(c, 0.0);
	CUSTOM = vec4(VELOCITY, 0.0);
}

void process() {
	vec3 p = TRANSFORM[3].xyz;
	// Each particle settles on its own shell radius; bass and beats inflate it.
	float shell = mix(shell_min, shell_max, hash(INDEX * 2654435761u + 7u));
	shell *= 1.0 + bass * bass_shell + kick * kick_shell;
	vec3 flow = vec3(0.0);
	float nearest = 1e9;
	vec3 to_nearest = vec3(0.0);

	for (int i = 0; i < node_count; i++) {
		vec3 d = nodes[i] - p;
		float r = length(d) + 1e-3;
		vec3 n = d / r;
		float f = 1.0 / (1.0 + r * r * falloff);
		// Pull toward / push away from the shell, orbit around the axis.
		flow += n * (r - shell) * attraction * f;
		flow += cross(axes[i], n) * swirl * (1.0 + mid * mid_swirl) * f;
		// Squash toward the node's equatorial plane.
		flow += axes[i] * dot(d, axes[i]) * flatten * f;
		if (r < nearest) {
			nearest = r;
			to_nearest = n;
		}
	}
	flow += flow_noise(p * turb_scale, turb_phase) * turbulence * (1.0 + mid * mid_turb);
	// Treble: jitter so the cloud shimmers.
	uint seed = INDEX * 9973u + uint(TIME * 30.0) * 131u;
	flow += random_unit(seed) * treble * treble_jitter;
	// Beat: blast away from the closest node.
	flow -= to_nearest * kick * kick_push;

	// Steer toward the flow; drag sets how tightly particles follow it.
	VELOCITY = mix(VELOCITY, flow, 1.0 - exp(-drag * DELTA));
	float sp = length(VELOCITY);
	float cap = max_speed * (1.0 + bass + kick * 2.0);
	if (sp > cap) {
		VELOCITY *= cap / sp;
	}

	// Age 0..1 over the particle's life, for fade in/out in the draw pass.
	CUSTOM.w += DELTA / LIFETIME;
	CUSTOM.xyz = VELOCITY;
	float age = CUSTOM.w;
	COLOR.a = smoothstep(0.0, 0.1, age) * (1.0 - smoothstep(0.75, 1.0, age));
}
