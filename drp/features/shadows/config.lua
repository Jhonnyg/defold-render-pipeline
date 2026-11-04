-- These bounds also define the shader metadata allocation; keep shadows.glsl in sync.
local M = {
	light_capacity = 64,
	view_capacity = 128,
	header_floats = 12,
	view_floats = 24,
}
M.buffer_floats = M.light_capacity * M.header_floats + M.view_capacity * M.view_floats

local function number(value, default, low, high)
	if type(value) ~= "number" or value ~= value then
		value = default
	end
	return math.max(low, math.min(high, value))
end

local function integer(value, default, low, high)
	return math.floor(number(value, default, low, high))
end

function M.resolve(settings, limits)
	settings, limits = settings or {}, limits or {}
	local size_limit = 4096
	for _, name in ipairs({ "max_texture_size_2d", "max_framebuffer_width", "max_framebuffer_height" }) do
		local value = limits[name]
		if value and value > 0 then
			size_limit = math.min(size_limit, value)
		end
	end

	-- Convert profile intent into bounded atlas and shader allocations.
	local quality = settings.quality or "off"
	local level = ({ hard = 1, pcf = 2, pcss = 3, pcss_high = 4 })[quality] or 0
	local size = integer(settings.atlas_size, 2048, 1, size_limit)
	local tile = integer(settings.tile_size, 256, 32, size)
	local directional_size = integer(settings.directional_atlas_size, 2048, 1, size_limit)
	local directional_tile = integer(settings.directional_tile_size, 1024, 32, directional_size)

	return {
		enabled = settings.enabled ~= false and level > 0,
		quality = quality,
		level = level,
		atlas_size = size,
		tile_size = tile,
		directional_atlas_size = directional_size,
		directional_tile_size = directional_tile,
		local_capacity = math.min(64, math.floor(size / tile)^2),
		directional_capacity = math.min(16, math.floor(directional_size / directional_tile)^2),
		max_shadowed_local_lights = integer(settings.max_shadowed_local_lights, 4, 0, 64),
		max_shadowed_directional_lights = integer(settings.max_shadowed_directional_lights, 1, 0, 4),
		directional_cascades = integer(settings.directional_cascades, 2, 1, 4),
		max_updates_per_frame = integer(settings.max_updates_per_frame, 32, 0, 128),
		distance = number(settings.distance, 100, 0.1, 100000),
		caster_distance = number(settings.caster_distance, 100, 0.1, 100000),
		cascade_blend = number(settings.cascade_blend, 0.1, 0, 0.3),
		split_lambda = number(settings.split_lambda, 0.6, 0, 1),
	}
end

return M
