// Particles with trails (thin lines or wide ribbons). They are born at a
// node and fly outward; the knobs bend that into straight needles
// (urchin), arcs toward a partner node (field lines) or twisting ribbons.
shader_type particles;

#include "res://shaders/common.gdshaderinc"

const int MAX_NODES = 6;

uniform int node_count = 4;
uniform vec3 nodes[MAX_NODES];
uniform vec3 axes[MAX_NODES];
uniform vec3 hues[MAX_NODES];

uniform float radial = 3.0;        // outward speed from the home node
uniform float partner_pull = 0.0;  // pull toward the next node: arcs between nodes
uniform float swirl = 0.0;         // orbit around the home node's axis
uniform float turbulence = 0.0;
uniform float turb_scale = 1.0;
uniform float turb_phase = 0.0;    // integrated in main.gd
uniform float drag = 1.0;          // how tightly particles follow the flow
uniform float twist = 0.0;         // ribbon roll speed around its direction
uniform float spawn_radius = 0.15;
uniform float white_share = 0.2;   // share of white trails among coloured ones
uniform float reach = 2.5;         // trails fade out this far from their node

uniform float bass = 0.0;
uniform float mid = 0.0;
uniform float kick = 0.0;
uniform float kick_burst = 2.0;    // extra outward speed on a beat

void start() {
	uint seed = INDEX * 7919u + RANDOM_SEED * 104729u + uint(NUMBER) * 31u;
	int k = int(hash(seed) * float(node_count)) % node_count;
	vec3 dir = random_unit(seed + 11u);
	if (RESTART_POSITION) {
		TRANSFORM = mat4(1.0);
		TRANSFORM[3].xyz = nodes[k] + dir * spawn_radius;
	}
	if (RESTART_VELOCITY) {
		VELOCITY = dir * max(radial, 0.5) * (0.6 + 0.8 * hash(seed + 5u));
	}
	vec3 c = hash(seed + 41u) < white_share ? vec3(1.0) : hues[k];
	COLOR = vec4(c, 0.0);
	// x: age 0..1, y: home node, z: per-particle random
	CUSTOM = vec4(0.0, float(k), hash(seed + 3u), 0.0);
}

void process() {
	int home = int(CUSTOM.y);
	vec3 p = TRANSFORM[3].xyz;
	vec3 out_vec = p - nodes[home];
	float r = length(out_vec) + 1e-3;
	vec3 n_out = out_vec / r;

	vec3 flow = n_out * radial * (1.0 + bass * 0.3);
	int partner = (home + 1) % node_count;
	vec3 to_partner = nodes[partner] - p;
	flow += normalize(to_partner + 1e-4) * partner_pull * min(length(to_partner), 2.0);
	flow += cross(axes[home], n_out) * swirl * (1.0 + mid * 0.5);
	flow += flow_noise(p * turb_scale, turb_phase + CUSTOM.z * 10.0) * turbulence;
	flow += n_out * kick * kick_burst;
	VELOCITY = mix(VELOCITY, flow, 1.0 - exp(-drag * DELTA));

	// Orientation: Y along the motion, X (the ribbon's width) rolling
	// around it, so flat ribbons twist as they fly.
	vec3 f = normalize(VELOCITY + vec3(0.0, 1e-4, 0.0));
	vec3 up = abs(f.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 side = normalize(cross(up, f));
	vec3 up2 = cross(f, side);
	float ang = TIME * twist + CUSTOM.z * TAU;
	vec3 x = side * cos(ang) + up2 * sin(ang);
	TRANSFORM[0].xyz = x;
	TRANSFORM[1].xyz = f;
	TRANSFORM[2].xyz = cross(x, f);

	CUSTOM.x += DELTA / LIFETIME;
	COLOR.a = smoothstep(0.0, 0.08, CUSTOM.x) * (1.0 - smoothstep(0.6, 1.0, CUSTOM.x))
		* (1.0 - smoothstep(reach * 0.6, reach, r));
}
