local M = {}

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function valid_vector(value)
	return finite(value[1]) and finite(value[2]) and finite(value[3])
end

local function vector(value)
	return vmath.vector3(value[1], value[2], value[3])
end

local function look(position, direction)
	local up = math.abs(direction.y) > 0.95 and vmath.vector3(1, 0, 0) or vmath.vector3(0, 1, 0)
	return vmath.matrix4_look_at(position, position + direction, up)
end

local function view(position, direction, up, projection, near, far)
	local matrix = up and vmath.matrix4_look_at(position, position + direction, up) or look(position, direction)
	return {
		view = matrix,
		projection = projection,
		matrix = projection * matrix,
		near = near,
		far = far,
	}
end

function M.local_light(light, config)
	local far = light.range
	if not finite(far) or not valid_vector(light.position) then
		return nil
	end
	if far <= 0.02 then
		return nil
	end

	local near = math.min(0.05, far * 0.01)
	local position = vector(light.position)

	-- A spot light uses its cone angle as the full perspective field of view.
	if light.type == 2 then
		if not finite(light.outer_cone) or not valid_vector(light.direction) then
			return nil
		end
		if light.outer_cone <= 0 or light.outer_cone >= math.pi then
			return nil
		end
		local direction = vector(light.direction)
		if vmath.length_sqr(direction) < 0.000001 then
			return nil
		end

		return {
			view(position, vmath.normalize(direction), nil,
				vmath.matrix4_perspective(light.outer_cone, 1, near, far), near, far),
		}
	end

	-- Keep cube-face order in sync with drp_shadow_point_face() in shadows.glsl.
	local result = {}
	local directions = {
		{ 1, 0, 0 },
		{ -1, 0, 0 },
		{ 0, 1, 0 },
		{ 0, -1, 0 },
		{ 0, 0, 1 },
		{ 0, 0, -1 },
	}
	local ups = {
		{ 0, -1, 0 },
		{ 0, -1, 0 },
		{ 0, 0, 1 },
		{ 0, 0, -1 },
		{ 0, -1, 0 },
		{ 0, -1, 0 },
	}

	-- Slight overlap keeps comparison taps around a cube face edge inside rendered geometry.
	local guard = math.min(0.8, 2 * math.max(2, light.softness) / (config.tile_size - 2))
	local projection = vmath.matrix4_perspective(2 * math.atan(1 / (1 - guard)), 1, near, far)
	for i = 1, 6 do
		result[i] = view(position, vector(directions[i]), vector(ups[i]), projection, near, far)
	end
	return result
end

local function point(inverse, x, y, z)
	local p = inverse * vmath.vector4(x, y, z, 1)
	return vmath.vector3(p.x / p.w, p.y / p.w, p.z / p.w)
end

function M.directional(light, camera, config)
	local near, far = camera.near, math.min(camera.far, config.distance)
	if near <= 0 or far <= near then
		return nil
	end
	if not valid_vector(light.direction) then
		return nil
	end
	local direction = vector(light.direction)
	if vmath.length_sqr(direction) < 0.000001 then
		return nil
	end

	direction = vmath.normalize(direction)

	-- Unproject the camera corners once, then interpolate each cascade along
	-- those world-space rays. This also supports orthographic cameras.
	local inverse = vmath.inv(camera.projection * camera.view)
	local near_points, far_points = {}, {}
	for _, xy in ipairs({ {-1,-1}, {1,-1}, {-1,1}, {1,1} }) do
		near_points[#near_points + 1] = point(inverse, xy[1], xy[2], -1)
		far_points[#far_points + 1] = point(inverse, xy[1], xy[2], 1)
	end

	-- Blend logarithmic and uniform splits to balance near/far resolution.
	local splits, result = {}, {}
	for i = 1, config.directional_cascades do
		local fraction = i / config.directional_cascades
		splits[i] = config.split_lambda * near * (far / near)^fraction
			+ (1 - config.split_lambda) * (near + (far - near) * fraction)
	end

	for i, split in ipairs(splits) do
		local previous = i == 1 and near or splits[i - 1]
		local overlap = i == 1 and 0 or (previous - (i == 2 and near or splits[i - 2])) * config.cascade_blend

		-- Include the previous cascade's blend region in this cascade's bounds.
		local corners, center = {}, vmath.vector3()
		for j = 1, 4 do
			local ray = far_points[j] - near_points[j]
			for _, depth in ipairs({previous - overlap, split}) do
				local p = near_points[j] + ray * ((depth - camera.near) / (camera.far - camera.near))
				corners[#corners + 1] = p
				center = center + p / 8
			end
		end

		local radius = 0
		for _, p in ipairs(corners) do
			radius = math.max(radius, vmath.length(p - center))
		end

		-- Sphere fitting avoids extent changes as the camera rotates; snapping in
		-- a fixed light basis prevents sub-texel translation shimmer.
		radius = math.ceil(radius * 16) / 16 + 0.01
		local basis = look(vmath.vector3(), direction)
		local light_center = basis * vmath.vector4(center.x, center.y, center.z, 1)
		local texel = 2 * radius / math.max(1, config.directional_tile_size - 2)
		light_center.x = math.floor(light_center.x / texel + 0.5) * texel
		light_center.y = math.floor(light_center.y / texel + 0.5) * texel
		local snapped = vmath.inv(basis) * light_center
		center = vmath.vector3(snapped.x, snapped.y, snapped.z)

		-- Extend depth beyond the visible slice to retain off-camera occluders.
		local distance = radius + config.caster_distance
		local projection = vmath.matrix4_orthographic(-radius, radius, -radius, radius, 0.01, 2 * distance)
		result[i] = view(center - direction * distance, direction, nil, projection, 0.01, 2 * distance)
	end
	return result, splits
end

-- Compare the actual view transforms, not the light-buffer submission revision.
function M.signature(views, geometry_revision)
	local values = { tostring(geometry_revision) }
	for _, item in ipairs(views) do
		for column = 0, 3 do
			for row = 0, 3 do
				values[#values + 1] = string.format("%.9g", item.matrix["m" .. row .. column])
			end
		end
	end
	return table.concat(values, ",")
end

return M
