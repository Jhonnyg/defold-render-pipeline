return {
	name = "balanced",
	description = "Default Forward+ profile balancing image quality and GPU cost.",
	extends = "compatibility",
	fallback = "compatibility",
	requirements = {
		"compute_shaders",
		"storage_buffers",
		"float_render_targets",
	},
	settings = {
		rendering = {
			path = "forward_plus",
			hdr = true,
		},
		lighting = {
			cluster_tile_size = 96,
			cluster_z_slices = 16,
			max_lights_per_cluster = 64,
		},
		shadows = {
			quality = "pcf",
			directional_cascades = 2,
			max_shadowed_local_lights = 4,
		},
		post = {
			gtao = true,
			gtao_resolution = 0.5,
			dof = false,
			temporal = false,
		},
	},
	platform_overrides = {
		html5 = {
			settings = {
				lighting = {
					max_lights_per_cluster = 48,
				},
				shadows = {
					max_shadowed_local_lights = 2,
				},
			},
		},
	},
}
