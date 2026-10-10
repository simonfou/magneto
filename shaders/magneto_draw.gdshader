// Draw pass: each particle is a soft additive streak, stretched along its
// velocity on screen so fast particles leave light trails. HDR brightness
// above 1 is what the WorldEnvironment glow picks up.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled;

uniform float size = 0.006;
uniform float stretch = 0.09;
uniform float intensity = 0.45;
uniform float energy = 0.0;  // overall loudness from main.gd

void vertex() {
	vec3 center = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	vec3 vel = (VIEW_MATRIX * vec4(INSTANCE_CUSTOM.xyz, 0.0)).xyz;
	vec2 dir = vel.xy;
	float sp = length(dir);
	dir = sp > 1e-4 ? dir / sp : vec2(1.0, 0.0);
	vec2 perp = vec2(-dir.y, dir.x);
	float s = size * (1.0 + energy * 0.8);
	float len = s + sp * stretch;
	// QuadMesh corners are at +-0.5.
	vec2 off = dir * VERTEX.x * 2.0 * len + perp * VERTEX.y * 2.0 * s;
	VERTEX = center + vec3(off, 0.0);
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float a = max(0.0, 1.0 - dot(q, q));
	a *= a;
	ALBEDO = COLOR.rgb * intensity * (1.0 + energy * 1.5);
	ALPHA = a * COLOR.a;
}
