// The "big black dots": an opaque dark sphere around a node with a thin
// glass-like rim. Being opaque it hides whatever passes behind it, so the
// particles sitting on its front surface read as dots on a black ball.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform vec3 rim_color = vec3(0.4, 1.0, 0.8);
uniform float rim = 1.0;
uniform float glass = 1.0;  // 1 = tinted glass with a glowing rim, 0 = black ball

void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 glassy = rim_color * (pow(f, 4.0) * rim * 1.6 + 0.012);
	// Black ball: pure black body, only a hairline of pale light at the edge.
	vec3 black = mix(rim_color, vec3(1.0), 0.5) * pow(f, 10.0) * rim * 0.9;
	ALBEDO = mix(black, glassy, glass);
}
