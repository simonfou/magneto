## Visual modes. Each one is a full set of parameters; main.gd blends from
## the current set to the target one, so switching is a smooth morph.
##   process -> uniforms of shaders/magneto_process.gdshader
##   draw    -> uniforms of shaders/magneto_draw.gdshader
##   scene   -> used by main.gd (nodes, camera, glow)
## Audio-reactive knobs: kick_* (beat onsets), bass_*, mid_*, treble_*.
## Flashes (kick_flash, white_flash, glow_pulse) are kept low on purpose:
## the flashing was the most chaotic part (2026-10-09).
## Shape: stretch 0 = round dots, higher = streaks; size_var = a few big
## soft particles; dof = out-of-focus particles grow into faint discs.

const LIST := [
	{
		"name": "Magnetosphere",
		"palette": [Color(0.25, 0.45, 1.0), Color(0.15, 0.85, 1.0), Color(0.85, 0.3, 1.0), Color(1.0, 0.5, 0.15)],
		"process": {
			"attraction": 2.0, "swirl": 2.4, "drag": 2.5, "max_speed": 4.0, "falloff": 1.5,
			"shell_min": 0.25, "shell_max": 1.4, "flatten": 0.0,
			"turbulence": 0.15, "turb_scale": 0.8,
			"kick_push": 3.0, "kick_shell": 0.25, "bass_shell": 0.15,
			"mid_swirl": 1.5, "mid_turb": 0.5, "treble_jitter": 0.6, "bound": 3.2,
		},
		"draw": {"size": 0.011, "stretch": 0.012, "intensity": 0.5, "size_var": 1.0, "dof": 0.35, "kick_flash": 0.5, "treble_sparkle": 0.6, "white_flash": 0.05},
		"scene": {"spread": 2.2, "node_speed": 1.0, "axis_align": 0.0, "cam_dist": 9.5, "cam_speed": 0.05,
			"cam_punch": 0.8, "glow": 0.7, "glow_pulse": 0.24, "hue_speed": 0.004, "turb_speed": 0.3},
	},
	{
		"name": "Galaxy",
		"palette": [Color(1.0, 0.75, 0.4), Color(0.4, 0.55, 1.0), Color(0.75, 0.4, 1.0), Color(0.3, 0.8, 1.0)],
		"process": {
			"attraction": 1.2, "swirl": 3.0, "drag": 2.0, "max_speed": 5.0, "falloff": 0.3,
			"shell_min": 0.3, "shell_max": 2.6, "flatten": 3.0,
			"turbulence": 0.1, "turb_scale": 1.0,
			"kick_push": 4.0, "kick_shell": 0.2, "bass_shell": 0.15,
			"mid_swirl": 1.2, "mid_turb": 0.3, "treble_jitter": 0.4, "bound": 3.2,
		},
		"draw": {"size": 0.006, "stretch": 0.035, "intensity": 0.28, "size_var": 0.5, "dof": 0.2, "kick_flash": 0.4, "treble_sparkle": 0.8, "white_flash": 0.0},
		"scene": {"spread": 0.25, "node_speed": 0.5, "axis_align": 1.0, "cam_dist": 9.5, "cam_speed": 0.04,
			"cam_punch": 0.5, "glow": 0.8, "glow_pulse": 0.20, "hue_speed": 0.003, "turb_speed": 0.2},
	},
	{
		"name": "Supernova",
		"palette": [Color(1.0, 0.35, 0.15), Color(1.0, 0.7, 0.2), Color(1.0, 0.2, 0.5), Color(0.6, 0.3, 1.0)],
		"process": {
			"attraction": 3.5, "swirl": 1.0, "drag": 3.0, "max_speed": 9.0, "falloff": 0.8,
			"shell_min": 0.15, "shell_max": 1.1, "flatten": 0.0,
			"turbulence": 0.3, "turb_scale": 1.2,
			"kick_push": 10.0, "kick_shell": 0.8, "bass_shell": 0.4,
			"mid_swirl": 1.0, "mid_turb": 0.5, "treble_jitter": 1.0, "bound": 3.0,
		},
		"draw": {"size": 0.007, "stretch": 0.1, "intensity": 0.24, "size_var": 0.3, "dof": 0.1, "kick_flash": 0.7, "treble_sparkle": 0.5, "white_flash": 0.15},
		"scene": {"spread": 1.2, "node_speed": 0.8, "axis_align": 0.3, "cam_dist": 10.0, "cam_speed": 0.08,
			"cam_punch": 2.0, "glow": 0.9, "glow_pulse": 0.40, "hue_speed": 0.01, "turb_speed": 0.5},
	},
	{
		"name": "Aurora",
		"palette": [Color(0.2, 1.0, 0.6), Color(0.2, 0.8, 1.0), Color(0.6, 0.3, 1.0), Color(0.1, 1.0, 0.9)],
		"process": {
			"attraction": 0.6, "swirl": 0.6, "drag": 1.5, "max_speed": 3.0, "falloff": 0.5,
			"shell_min": 0.7, "shell_max": 1.6, "flatten": 0.0,
			"turbulence": 1.0, "turb_scale": 0.7,
			"kick_push": 4.0, "kick_shell": 0.2, "bass_shell": 0.2,
			"mid_swirl": 0.5, "mid_turb": 2.0, "treble_jitter": 0.3, "bound": 3.2,
		},
		"draw": {"size": 0.004, "stretch": 0.15, "intensity": 0.35, "size_var": 0.2, "dof": 0.15, "kick_flash": 0.4, "treble_sparkle": 0.4, "white_flash": 0.0},
		"scene": {"spread": 2.0, "node_speed": 0.6, "axis_align": 0.5, "cam_dist": 9.5, "cam_speed": 0.03,
			"cam_punch": 0.4, "glow": 0.9, "glow_pulse": 0.20, "hue_speed": 0.006, "turb_speed": 0.25},
	},
	{
		"name": "Swarm",
		"palette": [Color(1.0, 0.5, 0.1), Color(1.0, 0.25, 0.2), Color(1.0, 0.85, 0.3), Color(0.9, 0.2, 0.6)],
		"process": {
			"attraction": 4.0, "swirl": 3.5, "drag": 6.0, "max_speed": 7.0, "falloff": 2.5,
			"shell_min": 0.15, "shell_max": 0.9, "flatten": 0.0,
			"turbulence": 0.4, "turb_scale": 2.0,
			"kick_push": 6.0, "kick_shell": 0.5, "bass_shell": 0.3,
			"mid_swirl": 2.0, "mid_turb": 0.8, "treble_jitter": 2.0, "bound": 3.2,
		},
		"draw": {"size": 0.008, "stretch": 0.0, "intensity": 0.6, "size_var": 0.7, "dof": 0.25, "kick_flash": 0.6, "treble_sparkle": 1.0, "white_flash": 0.05},
		"scene": {"spread": 2.2, "node_speed": 3.5, "axis_align": 0.0, "cam_dist": 9.5, "cam_speed": 0.06,
			"cam_punch": 1.0, "glow": 0.7, "glow_pulse": 0.40, "hue_speed": 0.008, "turb_speed": 1.0},
	},
]
