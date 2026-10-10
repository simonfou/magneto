// The "big black dots": an opaque dark sphere around a node with a thin
// glass-like rim. Being opaque it hides whatever passes behind it, so the
// particles sitting on its front surface read as dots on a black ball.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform vec3 rim_color = vec3(0.4, 1.0, 0.8);
uniform float rim = 1.0;
uniform float glass = 1.0;  // 1 = tinted glass with a glowing rim, 0 = black ball
uniform float lit = 0.0;    // 1 = only lit by its star: a crescent on that side
uniform vec3 light_pos = vec3(0.0);  // the star, world space
uniform vec3 light_color = vec3(1.0, 0.95, 0.9);

void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 glassy = rim_color * (pow(f, 4.0) * rim * 1.6 + 0.012);
	// Black ball: pure black body, only a hairline of pale light at the edge.
	vec3 black = mix(rim_color, vec3(1.0), 0.5) * pow(f, 10.0) * rim * 0.9;
	vec3 col = mix(black, glassy, glass);
	// Moon look (original ~0:15): an unlit black ball you only notice by what
	// it hides, with a thin crescent where its star lights the edge.
	vec3 l = normalize((VIEW_MATRIX * vec4(light_pos, 1.0)).xyz - VERTEX);
	float ndl = dot(NORMAL, l);
	vec3 moon = light_color * (pow(f, 3.0) * smoothstep(-0.05, 0.6, ndl) * 2.2 + pow(max(ndl, 0.0), 6.0) * 0.03);
	ALBEDO = mix(col, moon, lit);
}
