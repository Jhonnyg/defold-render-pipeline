return {
	name = "high",
	description = "Higher quality Forward+ profile for desktop and console-class hardware.",
	extends = "balanced",
	fallback = "balanced",
	settings = {
		lighting = {
			cluster_tile_size = 64,
			cluster_z_slices = 24,
			max_lights_per_cluster = 128,
		},
		shadows = {
			quality = "pcss",
			directional_cascades = 4,
			max_shadowed_local_lights = 12,
		},
		post = {
			gtao_quality = "high",
			dof = true,
			temporal = true,
		},
	},
}
