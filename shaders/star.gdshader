// A node drawn as a bright white star: hot core, soft halo, faint lens
// ring and thin cross rays. Billboard quad, additive, drawn over
// everything (it shines through the bubbles, like in the original).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

uniform vec3 tint = vec3(1.0, 0.95, 0.9);
uniform float glow = 1.0;

void vertex() {
	// Face the camera, keep the node's scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float r2 = dot(q, q);
	float r = sqrt(r2);
	float core = exp(-r2 * 140.0) * 5.0;
	float halo = exp(-r2 * 9.0) * 0.5;
	float ring = exp(-pow((r - 0.42) * 16.0, 2.0)) * 0.06;
	float rays = (exp(-abs(q.x) * 120.0) + exp(-abs(q.y) * 120.0)) * exp(-r * 4.0) * 0.35;
	float v = (core + halo + ring + rays) * glow * (1.0 - smoothstep(0.85, 1.0, r));
	ALBEDO = tint * v;
	ALPHA = 1.0;
}
