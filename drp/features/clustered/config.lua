-- CPU-side half of the clustered-lighting capacity contract.
-- Keep these values synchronized with /drp/shaders/clustered_config.glsl.
-- Defold does not currently expose build-time shader defines to Lua, so the
-- renderer validates and clamps every profile against this module.
return {
	shader_light_capacity = 64,
	max_lights_per_cluster = 64,
	-- Three 64-entry scan/candidate arrays, one 64-entry index array,
	-- and the shared allocation count and offset, all four-byte values.
	assignment_shared_memory_bytes = (3 * 64 + 64 + 2) * 4,
}
