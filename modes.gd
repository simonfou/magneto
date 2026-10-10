## Visual modes, modelled on frames of the original iTunes Magnetosphere
## (analysed 2026-10-09) plus one of our own (Aurora).
##
## Each mode only lists what differs from DEFAULTS; all() merges them.
## main.gd blends the live parameters toward the target mode, so switching
## is a smooth morph. Groups:
##   dots_process -> shaders/magneto_process.gdshader (orbiting dots)
##   dots_draw    -> shaders/magneto_draw.gdshader
##   lines        -> trail_process + trail_draw, thin tube trails
##   ribbons      -> trail_process + trail_draw, wide flat ribbons
##   scene        -> main.gd (nodes, stars, bubbles, camera, glow, breathing)
## A system with amount 0 is hidden. Flashes stay low on purpose: in
## testing, flashing read as the most chaotic part. Shape: stretch 0 = round dots.

const DEFAULTS := {
	"dots_process": {
		"attraction": 2.0, "swirl": 2.4, "drag": 2.5, "max_speed": 4.0, "falloff": 1.5,
		"shell_min": 0.25, "shell_max": 1.4, "flatten": 0.0,
		"turbulence": 0.15, "turb_scale": 0.8, "bound": 3.2,
		"kick_push": 3.0, "kick_shell": 0.25, "bass_shell": 0.15,
		"mid_swirl": 1.5, "mid_turb": 0.5, "treble_jitter": 0.6,
	},
	"dots_draw": {
		"amount": 1.0, "size": 0.02, "stretch": 0.0, "intensity": 0.6, "size_var": 1.0, "dof": 0.3,
		"kick_flash": 0.5, "treble_sparkle": 0.6, "white_flash": 0.05,
	},
	"lines": {
		"amount": 0.0, "radial": 3.0, "partner_pull": 0.0, "swirl": 0.0, "turbulence": 0.0,
		"turb_scale": 1.0, "drag": 1.5, "kick_burst": 2.0, "intensity": 0.6, "white_share": 0.3,
		"reach": 2.5,
	},
	"ribbons": {
		"amount": 0.0, "radial": 0.6, "partner_pull": 0.0, "swirl": 2.0, "turbulence": 1.2,
		"turb_scale": 0.8, "drag": 1.5, "twist": 2.0, "kick_burst": 1.0, "intensity": 0.3,
		"white_share": 0.6, "reach": 2.2,
	},
	"scene": {
		"spread": 2.2, "node_speed": 1.0, "axis_align": 0.0, "cam_dist": 9.5, "cam_speed": 0.05,
		"cam_punch": 0.8, "glow": 0.8, "glow_pulse": 0.2, "hue_speed": 0.003, "turb_speed": 0.3,
		"star_size": 0.6, "star_glow": 1.0, "bubble": 0.0, "breath_min": 0.06,
	},
}

const MODES := [
	{
		# Sparse coloured dots and big soft bokeh around white stars.
		"name": "Bokeh",
		"palette": [Color(1.0, 0.9, 0.75), Color(0.4, 0.9, 0.8), Color(0.7, 0.6, 1.0), Color(0.6, 1.0, 0.7)],
	},
	{
		# Black glass spheres around the stars, dots stuck on their surface.
		"name": "Bubbles",
		"palette": [Color(0.3, 1.0, 0.75), Color(0.2, 0.85, 0.9), Color(0.5, 1.0, 0.6), Color(0.85, 1.0, 0.95)],
		"dots_process": {"shell_min": 1.0, "shell_max": 1.08, "swirl": 1.2, "attraction": 4.0,
			"turbulence": 0.03, "treble_jitter": 0.15, "kick_push": 1.0},
		"dots_draw": {"size": 0.017, "size_var": 0.3, "dof": 0.2},
		"scene": {"bubble": 1.0, "spread": 2.6},
	},
	{
		# Thin curved lines arcing from star to star, like magnetic field lines.
		"name": "Field lines",
		"palette": [Color(1.0, 0.3, 0.9), Color(0.55, 0.4, 1.0), Color(0.9, 0.5, 1.0), Color(0.4, 0.5, 1.0)],
		"dots_draw": {"amount": 0.3, "size": 0.012},
		"lines": {"amount": 1.0, "radial": 1.5, "partner_pull": 1.8, "swirl": 0.8, "turbulence": 0.2, "intensity": 0.8,
			"reach": 3.0},
		"scene": {"spread": 2.0},
	},
	{
		# Straight needles bursting out of the stars, like a sea urchin.
		"name": "Urchin",
		"palette": [Color(0.75, 0.5, 1.0), Color(0.6, 0.4, 1.0), Color(0.9, 0.8, 1.0), Color(0.5, 0.6, 1.0)],
		"dots_draw": {"amount": 0.25},
		"lines": {"amount": 1.0, "radial": 3.0, "drag": 3.0, "kick_burst": 3.0, "intensity": 0.5, "white_share": 0.5,
			"reach": 1.8},
		"scene": {"spread": 1.6},
	},
	{
		# Wide flat ribbons twisting around the stars.
		"name": "Ribbons",
		"palette": [Color(0.85, 0.7, 1.0), Color(0.4, 0.9, 1.0), Color(1.0, 0.8, 0.95), Color(0.6, 0.6, 1.0)],
		"dots_draw": {"amount": 0.35, "size": 0.014},
		"ribbons": {"amount": 1.0},
		"scene": {"spread": 1.8},
	},
	{
		# Ours: long turbulent filaments in greens and violet.
		"name": "Aurora",
		"palette": [Color(0.2, 1.0, 0.6), Color(0.2, 0.8, 1.0), Color(0.6, 0.3, 1.0), Color(0.1, 1.0, 0.9)],
		"dots_process": {"attraction": 0.6, "swirl": 0.6, "drag": 1.5, "max_speed": 3.0, "falloff": 0.5,
			"shell_min": 0.7, "shell_max": 1.6, "turbulence": 1.0, "turb_scale": 0.7,
			"kick_push": 4.0, "kick_shell": 0.2, "bass_shell": 0.2, "mid_swirl": 0.5, "mid_turb": 2.0,
			"treble_jitter": 0.3},
		"dots_draw": {"size": 0.004, "stretch": 0.15, "intensity": 0.35, "size_var": 0.2, "dof": 0.15,
			"kick_flash": 0.4, "treble_sparkle": 0.4, "white_flash": 0.0},
		"scene": {"spread": 2.0, "cam_dist": 11.5, "node_speed": 0.6, "axis_align": 0.5, "cam_speed": 0.03,
			"cam_punch": 0.4, "glow": 0.9, "hue_speed": 0.006, "turb_speed": 0.25, "star_glow": 0.6},
	},
]

static var _all: Array = []


## Every mode with DEFAULTS filled in; same shape for all of them.
static func all() -> Array:
	if not _all.is_empty():
		return _all
	for m: Dictionary in MODES:
		var full := {"name": m.name, "palette": m.palette.duplicate()}
		for group: String in DEFAULTS:
			var values: Dictionary = DEFAULTS[group].duplicate()
			var over: Dictionary = m.get(group, {})
			for key in over:
				if not values.has(key):
					push_error("modes.gd: %s.%s.%s is not in DEFAULTS" % [m.name, group, key])
				values[key] = over[key]
			full[group] = values
		_all.append(full)
	return _all
