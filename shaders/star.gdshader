// A node drawn as a bright white star: hot core, soft halo, faint lens
// ring and thin cross rays. Billboard quad, additive, drawn over
// everything (it shines through the bubbles, like in the original).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

#include "res://shaders/star.gdshaderinc"
