// Draw pass for trail particles (TubeTrailMesh lines or RibbonTrailMesh
// ribbons): additive, fading toward the tail and at a ribbon's edges.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, particle_trails;

#include "res://shaders/common.gdshaderinc"

uniform float amount = 0.0;     // how much this mode uses this system
uniform float intensity = 0.6;
uniform float presence = 1.0;   // breathing, from main.gd
uniform float energy = 0.0;
uniform float kick = 0.0;
uniform float tail_flip = 0.0;  // 1 if the mesh's UV.y runs tail -> head
uniform float soft_edges = 0.0; // ribbons: fade toward the long edges

varying float shown;

void vertex() {
	shown = amount * presence_fade(uint(INSTANCE_ID), presence);
}

void fragment() {
	float along = mix(UV.y, 1.0 - UV.y, tail_flip);
	float fade = 1.0 - along;
	float edge = mix(1.0, 1.0 - pow(abs(UV.x - 0.5) * 2.0, 2.0), soft_edges);
	ALBEDO = COLOR.rgb * intensity * (1.0 + energy * 0.4 + kick * 0.5);
	ALPHA = COLOR.a * fade * edge * shown;
}
