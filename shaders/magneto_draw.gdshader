// Draw pass: each particle is a soft additive streak, stretched along its
// velocity on screen so fast particles leave light trails. HDR brightness
// above 1 is what the WorldEnvironment glow picks up.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled;

uniform float size = 0.006;
uniform float stretch = 0.09;
uniform float intensity = 0.45;
uniform float max_len = 0.35;  // cap on streak length (world units)

// Audio (0..1) from main.gd, and how hard each one hits.
uniform float energy = 0.0;
uniform float kick = 0.0;
uniform float treble = 0.0;
uniform float kick_flash = 1.5;     // brightness boost on a beat
uniform float white_flash = 0.3;    // colours bleach toward white on a beat
uniform float treble_sparkle = 1.0; // share of particles that flare with treble
uniform uint sparkle_seed = 0u;     // changes every few frames

varying float flare;

float hash(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return float(x) / 4294967295.0;
}

void vertex() {
	vec3 center = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	vec3 vel = (VIEW_MATRIX * vec4(INSTANCE_CUSTOM.xyz, 0.0)).xyz;
	vec2 dir = vel.xy;
	float sp = length(dir);
	dir = sp > 1e-4 ? dir / sp : vec2(1.0, 0.0);
	vec2 perp = vec2(-dir.y, dir.x);

	// A few random particles flare up while treble is loud.
	float chance = treble * treble * 0.12 * treble_sparkle;
	flare = hash(uint(INSTANCE_ID) * 747796405u + sparkle_seed) < chance ? 1.0 : 0.0;

	float s = size * (1.0 + energy * 0.4 + kick * 0.6 + flare * 1.5);
	float len = s + min(sp * stretch, max_len);
	// QuadMesh corners are at +-0.5.
	vec2 off = dir * VERTEX.x * 2.0 * len + perp * VERTEX.y * 2.0 * s;
	VERTEX = center + vec3(off, 0.0);
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float a = max(0.0, 1.0 - dot(q, q));
	a *= a;
	vec3 c = mix(COLOR.rgb, vec3(1.0), clamp(kick * white_flash + flare * 0.6, 0.0, 1.0));
	float b = intensity * (1.0 + energy * 0.8 + kick * kick_flash + flare * 4.0);
	ALBEDO = c * b;
	ALPHA = a * COLOR.a;
}
