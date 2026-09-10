return {
	name = "ultra",
	description = "Maximum-quality experimental profile for high-end hardware.",
	extends = "high",
	fallback = "high",
	settings = {
		rendering = {
			render_scale = 1.25,
		},
		lighting = {
			cluster_tile_size = 48,
			cluster_z_slices = 32,
			max_lights_per_cluster = 256,
		},
		shadows = {
			quality = "pcss_high",
			max_shadowed_local_lights = 24,
		},
		post = {
			gtao_quality = "ultra",
		},
	},
}
