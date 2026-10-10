// Same star, but depth-tested: a black ball in front hides it.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://shaders/star.gdshaderinc"
