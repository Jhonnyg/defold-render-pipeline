local M = {}

function M.run()
	local saved = {}
	for _, name in ipairs({ "sys", "graphics", "vmath", "render", "camera", "drp_native" }) do
		saved[name] = rawget(_G, name)
	end
	local width, height = 960, 640
	local camera_near = 0.1
	local build_resources = "1"
	local projection = { m00 = 1, m11 = 1, m22 = 1, m33 = 1 }
	local calls, buffers, next_id = {}, {}, 0
	local selected_compute
	local limits = {
		max_storage_buffers_per_stage = 8,
		max_compute_workgroup_size_x = 256,
		max_compute_workgroup_size_y = 256,
		max_compute_workgroup_size_z = 64,
		max_compute_workgroup_invocations = 256,
		max_compute_shared_memory_size = 32768,
		max_uniform_buffer_range = 65536,
		max_storage_buffer_range = 134217728,
	}
	_G.sys = {
		get_config = function(name, default)
			return name == "drp.clustered_resources" and build_resources or default
		end,
		get_config_number = function(_, default) return default end,
		get_sys_info = function() return { system_name = "Windows" } end,
	}
	_G.graphics = setmetatable({}, { __index = function(_, key) return key end })
	_G.vmath = {
		vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end,
		matrix4 = function(value)
			local copy = {}; for key, item in pairs(value) do copy[key] = item end; return copy
		end,
		inv = function(value) return value end,
	}
	_G.render = setmetatable({
		predicate = function(tags) return tags[1] end,
		constant_buffer = function() return {} end,
		get_window_width = function() return width end,
		get_window_height = function() return height end,
		set_compute = function(name) selected_compute = name end,
		dispatch_compute = function(x, y, z)
			assert(x <= 65535 and y <= 65535 and z <= 65535, "dispatch exceeds device limit")
			calls[#calls + 1] = { name = selected_compute, x = x, y = y, z = z }
		end,
	}, { __index = function() return function() end end })
	_G.camera = {
		get_cameras = function() return { 1 } end,
		get_enabled = function() return true end,
		get_view = function() return projection end,
		get_projection = function() return projection end,
		get_near_z = function() return camera_near end,
		get_far_z = function() return 100 end,
	}
	_G.drp_native = {
		get_capabilities = function()
			return { features = { compute_shaders = true, storage_buffers = true }, limits = limits }
		end,
		create_storage_buffer = function(size)
			next_id = next_id + 1; buffers[next_id] = size; return next_id
		end,
		resize_storage_buffer = function(id, size) assert(buffers[id]); buffers[id] = size; return true end,
		bind_storage_buffer = function(id) assert(buffers[id], "deleted buffer rebound"); return true end,
		unbind_storage_buffer = function(id) assert(buffers[id]); return true end,
		delete_storage_buffer = function(id) assert(buffers[id]); buffers[id] = nil; return true end,
		reset = function() assert(next(buffers) == nil, "feature leaked buffers"); return true end,
	}

	local pipeline = require("drp.pipeline")
	local function frame()
		calls = {}
		local _, err = pipeline.begin_frame(1 / 60, width, height)
		assert(not err, err)
		assert(pipeline.render())
		return assert(pipeline.get_feature_diagnostics("clustered"))
	end
	local function count_buffers()
		local count = 0; for _ in pairs(buffers) do count = count + 1 end; return count
	end

	pipeline.finalize()
	assert(pipeline.initialize({ quality = "ultra", strict_capabilities = true }))
	width, height = 3840, 2160
	local diagnostics = frame()
	assert(diagnostics.cluster_count == 115200)
	local assignment = calls[#calls]
	assert(assignment.name == "drp_cluster_assign")
	assert(assignment.x * assignment.y * assignment.z == diagnostics.cluster_count)
	assert(assignment.x == 80 and assignment.y == 45 and assignment.z == 32)
	frame()
	assert(#calls == 2, "stable projection should reuse cluster bounds")
	projection.m00 = 2
	frame()
	assert(#calls == 3, "projection changes must rebuild bounds")

	-- Clip ranges crossing the eye cannot use logarithmic depth slicing.
	camera_near = -1
	frame()
	assert(#calls == 0, "non-positive near planes must use conventional shading")
	camera_near = 0.1

	-- Change profile and viewport repeatedly, checking actual allocation lifetime.
	for index = 1, 60 do
		local profile = ({ "balanced", "high", "ultra", "compatibility" })[(index - 1) % 4 + 1]
		assert(pipeline.set_quality(profile))
		width, height = 640 + index * 8, 480 + index * 4
		frame()
		assert(count_buffers() == (profile == "compatibility" and 0 or 6))
	end
	pipeline.finalize()

	local minima = {
		max_storage_buffers_per_stage = 6,
		max_compute_workgroup_size_x = 64,
		max_compute_workgroup_size_y = 4,
		max_compute_workgroup_size_z = 4,
		max_compute_workgroup_invocations = 64,
		max_compute_shared_memory_size = 1032,
		max_uniform_buffer_range = 4112,
	}
	for name, minimum in pairs(minima) do
		local original = limits[name]
		for _, strict in ipairs({ false, true }) do
			limits[name] = minimum - 1
			assert(pipeline.initialize({ quality = "high", strict_capabilities = strict }))
			assert(pipeline.get_effective_quality() == "compatibility", name .. " must reject clustering")
			frame()
			assert(#calls == 0 and count_buffers() == 0)
			pipeline.finalize()
		end
		limits[name] = minimum
		assert(pipeline.initialize({ quality = "high", strict_capabilities = true }))
		assert(pipeline.get_effective_quality() == "high", name .. " must accept its exact minimum")
		pipeline.finalize()
		limits[name] = original
	end

	local bindings = limits.max_storage_buffers_per_stage
	limits.max_storage_buffers_per_stage = nil
	assert(pipeline.initialize({ quality = "balanced", strict_capabilities = true }))
	assert(pipeline.get_effective_quality() == "compatibility")
	pipeline.finalize()
	limits.max_storage_buffers_per_stage = bindings

	-- A supported pipeline must also fall back on a runtime capability change.
	assert(pipeline.initialize({ quality = "balanced" }))
	width, height = 960, 640
	frame()
	assert(pipeline.set_capabilities({ limits = { max_storage_buffers_per_stage = 4 } }))
	frame()
	assert(pipeline.get_effective_quality() == "compatibility" and count_buffers() == 0 and #calls == 0)
	assert(pipeline.set_capabilities({ limits = { max_storage_buffer_range = 35840 } }))
	diagnostics = frame()
	assert(diagnostics.max_lights_per_cluster == 8 and diagnostics.capacity_clamped)
	assert(diagnostics.buffer_sizes.cluster_bounds == 35840)
	assert(diagnostics.buffer_sizes.cluster_light_indices == 35840)
	pipeline.finalize()

	-- A compatibility export is a permanent resource constraint, even if an
	-- application tries to override capabilities or select a clustered profile.
	build_resources = "0"
	assert(pipeline.initialize({ quality = "ultra", capabilities = { features = { clustered_resources = true } } }))
	assert(pipeline.get_effective_quality() == "compatibility")
	frame()
	assert(#calls == 0 and count_buffers() == 0)
	assert(pipeline.set_quality("balanced"))
	frame()
	assert(pipeline.get_effective_quality() == "compatibility" and #calls == 0)
	local rejected, rejection = pipeline.set_runtime_overrides({ rendering = { path = "forward_plus" } })
	assert(not rejected and rejection, "runtime overrides must be validated before activation")
	assert(pipeline.set_quality("compatibility"), "a rejected override must not poison later requests")
	frame()
	assert(#calls == 0)
	pipeline.finalize()

	for _, name in ipairs({ "sys", "graphics", "vmath", "render", "camera", "drp_native" }) do
		_G[name] = saved[name]
	end
	return true
end

return M
