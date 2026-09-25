local config = require("drp.features.clustered.config")

local M = {}

-- Keep these aligned with the compute layouts and shared arrays. A known
-- insufficient limit rejects the profile even when strict mode is disabled.
local required_limits = {
	{ "max_storage_buffers_per_stage", 6 },
	{ "max_compute_workgroup_size_x", 64 },
	{ "max_compute_workgroup_size_y", 4 },
	{ "max_compute_workgroup_size_z", 4 },
	{ "max_compute_workgroup_invocations", 64 },
	{ "max_compute_shared_memory_size", config.assignment_shared_memory_bytes },
	{ "max_uniform_buffer_range", 16 + config.shader_light_capacity * 64 },
}

function M.missing_limits(capabilities)
	local missing = {}
	local limits = capabilities.limits or {}
	for _, requirement in ipairs(required_limits) do
		local name, minimum = requirement[1], requirement[2]
		local value = limits[name]
		if type(value) == "number" and value < minimum then
			missing[#missing + 1] = string.format("%s=%g (requires %d)", name, value, minimum)
		elseif type(value) ~= "number" and capabilities.strict then
			missing[#missing + 1] = string.format("%s is unknown (requires %d)", name, minimum)
		end
	end
	return missing
end

return M
