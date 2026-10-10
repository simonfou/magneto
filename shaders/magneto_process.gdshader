// Particle physics: a velocity field built from a handful of moving
// "magnetic" nodes. Particles settle on shells around each node and orbit
// its axis; they steer toward the field rather than accelerate, so the
// cloud stays stable. Audio uniforms
// (set from main.gd every frame) push the field around.
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
uniform float spawn_radius = 1.6;

// Audio, all roughly 0..1.
uniform float bass = 0.0;
uniform float mid = 0.0;
uniform float treble = 0.0;
uniform float kick = 0.0;  // spikes on a bass onset, decays in main.gd

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
	// Each particle settles on its own shell radius around the nodes.
	float shell = mix(0.6, 1.1, hash(INDEX * 2654435761u + 7u));
	vec3 flow = vec3(0.0);
	float nearest = 1e9;
	vec3 to_nearest = vec3(0.0);

	for (int i = 0; i < node_count; i++) {
		vec3 d = nodes[i] - p;
		float r = length(d) + 1e-3;
		vec3 n = d / r;
		float f = 1.0 / (1.0 + r * r * 1.5);
		// Pull toward / push away from the shell, orbit around the axis.
		flow += n * (r - shell) * attraction * f;
		flow += cross(axes[i], n) * swirl * (1.0 + mid * 0.8) * f;
		if (r < nearest) {
			nearest = r;
			to_nearest = n;
		}
	}
	// Treble: a bit of jitter so the cloud shimmers.
	uint seed = INDEX * 9973u + uint(TIME * 30.0) * 131u;
	flow += random_unit(seed) * treble * 0.8;

	// Steer toward the flow; drag sets how tightly particles follow it.
	VELOCITY = mix(VELOCITY, flow, 1.0 - exp(-drag * DELTA));
	// Bass onset: blast particles away from the closest node.
	VELOCITY -= to_nearest * kick * 12.0 * DELTA;
	float sp = length(VELOCITY);
	float cap = max_speed * (1.0 + bass);
	if (sp > cap) {
		VELOCITY *= cap / sp;
	}

	// Age 0..1 over the particle's life, for fade in/out in the draw pass.
	CUSTOM.w += DELTA / LIFETIME;
	CUSTOM.xyz = VELOCITY;
	float age = CUSTOM.w;
	COLOR.a = smoothstep(0.0, 0.1, age) * (1.0 - smoothstep(0.75, 1.0, age));
}
