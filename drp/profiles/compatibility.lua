return {
	name = "compatibility",
	description = "Portable baseline that does not require compute shaders or storage buffers.",
	requirements = {},
	settings = {
		rendering = {
			path = "forward",
			render_scale = 1.0,
			hdr = false,
		},
		lighting = {
			max_lights_per_object = 8,
		},
		shadows = {
			quality = "hard",
			directional_cascades = 1,
			max_shadowed_local_lights = 1,
		},
		post = {
			gtao = false,
			dof = false,
			temporal = false,
		},
	},
}
