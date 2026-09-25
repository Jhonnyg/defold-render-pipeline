local clustered = require("drp.features.clustered.config")

return {
	name = "balanced",
	description = "Default Forward+ profile balancing image quality and GPU cost.",
	extends = "compatibility",
	fallback = "compatibility",
	requirements = {
		"compute_shaders",
		"storage_buffers",
	},
	settings = {
		rendering = {
			path = "forward_plus",
			hdr = true,
		},
		lighting = {
			cluster_tile_size = 96,
			cluster_z_slices = 16,
			max_lights_per_cluster = clustered.max_lights_per_cluster,
			-- Actual clustered PBR is the normal path. The occupancy heatmap remains
			-- available as an explicit diagnostic override.
			cluster_debug = false,
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
