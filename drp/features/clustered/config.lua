-- CPU-side half of the clustered-lighting capacity contract.
-- Keep these values synchronized with /drp/shaders/clustered_config.glsl.
-- Defold does not currently expose build-time shader defines to Lua, so the
-- renderer validates and clamps every profile against this module.
return {
	shader_light_capacity = 64,
	max_lights_per_cluster = 64,
}
