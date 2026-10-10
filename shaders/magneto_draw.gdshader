// Draw pass: each particle is a soft additive sprite. With stretch 0 it is
// a round glowing dot (the Magnetosphere look); higher stretch turns it
// into a streak along its on-screen velocity. A few particles are big and
// soft (size_var), and particles away from the focus distance grow into
// faint out-of-focus discs (dof). HDR brightness above 1 feeds the glow.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled;

uniform float size = 0.006;
uniform float stretch = 0.09;
uniform float intensity = 0.45;
uniform float amount = 1.0;      // how much this mode uses the dots (0 = hidden)
uniform float presence = 1.0;    // breathing, from main.gd: share of particles shown
uniform float max_len = 0.35;    // cap on streak length (world units)
uniform float size_var = 0.0;    // 0 = all the same size, 1 = a few big soft ones
uniform float dof = 0.0;         // blur growth per unit away from focus
uniform float focus_dist = 9.0;  // camera to scene centre, from main.gd

// Audio (0..1) from main.gd, and how hard each one hits.
uniform float energy = 0.0;
uniform float kick = 0.0;
uniform float treble = 0.0;
uniform float kick_flash = 0.5;     // brightness boost on a beat
uniform float white_flash = 0.05;   // colours bleach toward white on a beat
uniform float treble_sparkle = 1.0; // share of particles that flare with treble
uniform uint sparkle_seed = 0u;     // changes every few frames

varying float flare;
varying float blur;
varying float dim;
varying float shown;

#include "res://shaders/common.gdshaderinc"

void vertex() {
	vec3 center = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	vec3 vel = (VIEW_MATRIX * vec4(INSTANCE_CUSTOM.xyz, 0.0)).xyz;
	vec2 dir = vel.xy;
	float sp = length(dir);
	dir = sp > 1e-4 ? dir / sp : vec2(1.0, 0.0);
	vec2 perp = vec2(-dir.y, dir.x);
	uint id = uint(INSTANCE_ID);
	shown = amount * presence_fade(id, presence);

	// A few random particles flare up while treble is loud.
	float chance = treble * treble * 0.06 * treble_sparkle;
	flare = hash(id * 747796405u + sparkle_seed) < chance ? 1.0 : 0.0;

	// Size: mostly small, a long tail of big ones (pow pushes most to 0).
	float big = 1.0 + pow(hash(id * 2891336453u + 1u), 8.0) * size_var * 5.0;
	// Depth of field: the further from the focus plane, the bigger and fainter.
	blur = clamp(abs(-center.z - focus_dist) * dof, 0.0, 4.0);
	float grow = big * (1.0 + blur);
	// Spread the same light over a bigger disc so big ones don't blow out.
	dim = 1.0 / pow(grow, 1.6);

	float s = size * grow * (1.0 + energy * 0.3 + kick * 0.3 + flare * 0.8);
	float len = s + min(sp * stretch, max_len);
	// QuadMesh corners are at +-0.5.
	vec2 off = dir * VERTEX.x * 2.0 * len + perp * VERTEX.y * 2.0 * s;
	VERTEX = center + vec3(off, 0.0);
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float r2 = dot(q, q);
	// Sharp particles: soft glowing dot. Blurred ones: flat disc with a soft
	// rim, like camera bokeh.
	float dot_shape = max(0.0, 1.0 - r2);
	dot_shape *= dot_shape;
	float disc = 1.0 - smoothstep(0.6, 1.0, r2);
	float a = mix(dot_shape, disc * 0.5, clamp(blur * 0.5, 0.0, 1.0));
	vec3 c = mix(COLOR.rgb, vec3(1.0), clamp(kick * white_flash + flare * 0.3, 0.0, 1.0));
	float b = intensity * dim * (1.0 + energy * 0.4 + kick * kick_flash + flare * 1.5);
	ALBEDO = c * b;
	ALPHA = a * COLOR.a * shown;
}
