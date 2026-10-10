// The "big black dots": an opaque dark sphere around a node with a thin
// glass-like rim. Being opaque it hides whatever passes behind it, so the
// particles sitting on its front surface read as dots on a black ball.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform vec3 rim_color = vec3(0.4, 1.0, 0.8);
uniform float rim = 1.0;

void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = rim_color * (pow(f, 4.0) * rim * 1.6 + 0.012);
}
