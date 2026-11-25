local M = {}

-- Each slice searches both directions. Higher quality increases spatial
-- samples without introducing temporal history or motion-vector dependencies.
M.qualities = {
	low = { slices = 2, steps = 4 },
	medium = { slices = 3, steps = 6 },
	high = { slices = 4, steps = 8 },
	ultra = { slices = 6, steps = 8 },
}

local function finite(value, fallback)
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return fallback
	end
	return value
end

local function clamp(value, minimum, maximum, fallback)
	return math.max(minimum, math.min(maximum, finite(value, fallback)))
end

function M.resolve(post)
	post = type(post) == "table" and post or {}
	local quality = M.qualities[post.gtao_quality] and post.gtao_quality or "medium"
	return {
		enabled = post.gtao == true,
		resolution = clamp(post.gtao_resolution, 0.25, 1, 0.5),
		quality = quality,
		slices = M.qualities[quality].slices,
		steps = M.qualities[quality].steps,
		-- Keep Lua doubles representable and radius arithmetic finite on the GPU.
		radius = clamp(post.gtao_radius, 0.001, 1000000, 0.5),
		intensity = clamp(post.gtao_intensity, 0, 4, 1),
		power = clamp(post.gtao_power, 0.1, 4, 1),
		-- Horizon cosine offset: prevents nearly coplanar samples self-occluding.
		bias = clamp(post.gtao_bias, 0, 0.25, 0.02),
	}
end

return M
