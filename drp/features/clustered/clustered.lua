local native = require("drp.native")
local resources = require("drp.resources")

local M = {}

local MAX_SHADER_LIGHTS = 64
local MAX_LIGHTS_PER_CLUSTER = 64
local STORAGE_SET = 1

local BUFFER_DESCRIPTORS = {
	{ name = "cluster_bounds", binding = 0, bytes_per_cluster = 32 },
	{ name = "cluster_depth_ranges", binding = 1, bytes_per_tile = 16 },
	{ name = "cluster_metadata", binding = 2, bytes_per_cluster = 8 },
	{ name = "cluster_light_indices", binding = 3, bytes_per_index = 4 },
	{ name = "cluster_counters", binding = 4, fixed_size = 16 },
	{ name = "cluster_overflow", binding = 5, bytes_per_cluster = 4 },
}

local state = {
	enabled = false,
	available = false,
	render_available = false,
	warned = false,
	buffers = {},
	depth_target = nil,
	width = 0,
	height = 0,
	grid_x = 0,
	grid_y = 0,
	grid_z = 0,
	tile_size = 0,
	max_lights_per_cluster = 0,
	index_capacity = 0,
}

local function ceil_div(value, divisor)
	return math.floor((value + divisor - 1) / divisor)
end

local function active_camera()
	if not _G.camera then
		return nil
	end
	local cameras = camera.get_cameras()
	for index = #cameras, 1, -1 do
		if camera.get_enabled(cameras[index]) then
			return cameras[index]
		end
	end
	return nil
end

local function clustered_requested(context)
	local settings = context.profile and context.profile.settings or nil
	local rendering = settings and settings.rendering or nil
	return rendering and rendering.path == "forward_plus"
end

local function warn_once(message)
	if not state.warned then
		print("DRP clustered lighting disabled: " .. message)
		state.warned = true
	end
end

local function delete_depth_target()
	if state.depth_target and state.render_available then
		render.delete_render_target(state.depth_target)
		state.depth_target = nil
	end
end

local function delete_buffers()
	if native.is_available() then
		for _, descriptor in ipairs(BUFFER_DESCRIPTORS) do
			local handle = state.buffers[descriptor.name]
			if handle then
				native.unbind_storage_buffer(handle)
				native.delete_storage_buffer(handle)
			end
		end
	end
	state.buffers = {}
end

local function reset_allocations()
	delete_depth_target()
	delete_buffers()
	state.available = false
	state.width = 0
	state.height = 0
	state.grid_x = 0
	state.grid_y = 0
	state.grid_z = 0
	state.tile_size = 0
	state.max_lights_per_cluster = 0
	state.index_capacity = 0
end

local function buffer_size(descriptor, cluster_count, tile_count, index_capacity)
	if descriptor.fixed_size then
		return descriptor.fixed_size
	elseif descriptor.bytes_per_cluster then
		return descriptor.bytes_per_cluster * cluster_count
	elseif descriptor.bytes_per_tile then
		return descriptor.bytes_per_tile * tile_count
	end
	return descriptor.bytes_per_index * index_capacity
end

local function create_depth_target(width, height)
	local color = {
		format = graphics.TEXTURE_FORMAT_RGBA32F,
		width = width,
		height = height,
		min_filter = graphics.TEXTURE_FILTER_NEAREST,
		mag_filter = graphics.TEXTURE_FILTER_NEAREST,
		u_wrap = graphics.TEXTURE_WRAP_CLAMP_TO_EDGE,
		v_wrap = graphics.TEXTURE_WRAP_CLAMP_TO_EDGE,
		flags = render.TEXTURE_BIT,
	}
	local depth = {
		format = graphics.TEXTURE_FORMAT_DEPTH,
		width = width,
		height = height,
		min_filter = graphics.TEXTURE_FILTER_NEAREST,
		mag_filter = graphics.TEXTURE_FILTER_NEAREST,
		u_wrap = graphics.TEXTURE_WRAP_CLAMP_TO_EDGE,
		v_wrap = graphics.TEXTURE_WRAP_CLAMP_TO_EDGE,
		flags = render.TEXTURE_BIT,
	}
	return render.render_target("drp_cluster_depth", {
		[graphics.BUFFER_TYPE_COLOR0_BIT] = color,
		[graphics.BUFFER_TYPE_DEPTH_BIT] = depth,
	})
end

local function configure(context, width, height)
	reset_allocations()
	if not state.enabled or width < 1 or height < 1 then
		return
	end
	if not native.is_available() then
		warn_once("the native storage-buffer bridge is unavailable")
		return
	end

	local features = context.capabilities and context.capabilities.features or {}
	if features.compute_shaders == false or features.storage_buffers == false then
		warn_once("compute shaders or storage buffers are unsupported")
		return
	end

	local lighting = context.profile.settings.lighting or {}
	local tile_size = math.max(8, math.floor(lighting.cluster_tile_size or 96))
	local grid_z = math.max(1, math.floor(lighting.cluster_z_slices or 16))
	local max_lights = math.max(1, math.floor(lighting.max_lights_per_cluster or 64))
	max_lights = math.min(max_lights, MAX_LIGHTS_PER_CLUSTER)

	local grid_x = ceil_div(width, tile_size)
	local grid_y = ceil_div(height, tile_size)
	local tile_count = grid_x * grid_y
	local cluster_count = tile_count * grid_z
	local index_capacity = cluster_count * max_lights
	local maximum_range = context.capabilities and context.capabilities.limits and
		context.capabilities.limits.max_storage_buffer_range or nil
	if maximum_range and maximum_range > 0 then
		index_capacity = math.min(index_capacity, math.floor(maximum_range / 4))
	end

	local created = {}
	for _, descriptor in ipairs(BUFFER_DESCRIPTORS) do
		local size = buffer_size(descriptor, cluster_count, tile_count, index_capacity)
		if maximum_range and maximum_range > 0 and size > maximum_range then
			for _, handle in ipairs(created) do
				native.delete_storage_buffer(handle)
			end
			state.buffers = {}
			warn_once(descriptor.name .. " exceeds the device storage-buffer limit")
			return
		end
		local ok, handle = pcall(native.create_storage_buffer, size, native.BUFFER_USAGE_DYNAMIC_DRAW)
		if not ok then
			for _, created_handle in ipairs(created) do
				native.delete_storage_buffer(created_handle)
			end
			state.buffers = {}
			warn_once(tostring(handle))
			return
		end
		state.buffers[descriptor.name] = handle
		created[#created + 1] = handle
	end

	local target_ok, target = pcall(create_depth_target, width, height)
	if not target_ok then
		delete_buffers()
		warn_once("failed to create the linear-depth render target: " .. tostring(target))
		return
	end
	state.depth_target = target
	state.width = width
	state.height = height
	state.grid_x = grid_x
	state.grid_y = grid_y
	state.grid_z = grid_z
	state.tile_size = tile_size
	state.max_lights_per_cluster = max_lights
	state.index_capacity = index_capacity
	state.available = true
	state.warned = false
end

local function bind_cluster_buffers()
	for _, descriptor in ipairs(BUFFER_DESCRIPTORS) do
		native.bind_storage_buffer(state.buffers[descriptor.name], STORAGE_SET, descriptor.binding)
	end
end

local function make_constants(view, projection, near_z, far_z)
	local common = render.constant_buffer()
	common.cluster_projection = projection
	common.cluster_grid = vmath.vector4(
		state.grid_x,
		state.grid_y,
		state.grid_z,
		state.max_lights_per_cluster
	)
	common.cluster_screen = vmath.vector4(
		state.width,
		state.height,
		state.tile_size,
		1.0 / state.tile_size
	)
	common.cluster_z_params = vmath.vector4(near_z, far_z, 0, 0)

	local build = render.constant_buffer()
	build.inverse_projection = vmath.inv(projection)
	build.cluster_grid = common.cluster_grid
	build.cluster_screen = common.cluster_screen
	build.cluster_z_params = common.cluster_z_params

	local depth = render.constant_buffer()
	depth.cluster_grid = common.cluster_grid
	depth.cluster_screen = common.cluster_screen
	depth.cluster_z_params = common.cluster_z_params

	local assign = render.constant_buffer()
	assign.view_matrix = view
	assign.cluster_grid = common.cluster_grid
	assign.cluster_z_params = common.cluster_z_params
	assign.cluster_limits = vmath.vector4(
		state.max_lights_per_cluster,
		state.index_capacity,
		MAX_SHADER_LIGHTS,
		0
	)

	return common, build, depth, assign
end

local function render_depth_prepass(camera_component)
	render.set_render_target(state.depth_target)
	render.set_viewport(0, 0, state.width, state.height)
	render.set_camera(camera_component, { use_frustum = true })
	render.clear({
		[graphics.BUFFER_TYPE_COLOR0_BIT] = vmath.vector4(0, 0, 0, 0),
		[graphics.BUFFER_TYPE_DEPTH_BIT] = 1,
	})
	render.enable_state(graphics.STATE_DEPTH_TEST)
	render.set_depth_mask(true)

	render.enable_state(graphics.STATE_CULL_FACE)
	render.enable_material("drp_cluster_linear_depth_opaque")
	render.draw(state.opaque)
	render.disable_material()

	render.disable_state(graphics.STATE_CULL_FACE)
	render.enable_material("drp_cluster_linear_depth_mask")
	render.draw(state.mask)
	render.disable_material()
	render.disable_state(graphics.STATE_DEPTH_TEST)
	render.set_render_target(render.RENDER_TARGET_DEFAULT)
end

local function build_clusters(build, depth, assign)
	render.set_compute("drp_cluster_depth_reduce")
	render.enable_texture(0, state.depth_target, graphics.BUFFER_TYPE_COLOR0_BIT)
	render.dispatch_compute(ceil_div(state.grid_x, 8), ceil_div(state.grid_y, 8), 1, {
		constants = depth,
	})
	render.disable_texture(0)

	render.set_compute("drp_cluster_reset")
	render.dispatch_compute(1, 1, 1)

	render.set_compute("drp_cluster_build")
	render.dispatch_compute(
		ceil_div(state.grid_x, 4),
		ceil_div(state.grid_y, 4),
		ceil_div(state.grid_z, 4),
		{ constants = build }
	)

	render.set_compute("drp_cluster_assign")
	render.dispatch_compute(state.grid_x * state.grid_y * state.grid_z, 1, 1, {
		constants = assign,
	})
	render.set_compute()
end

local function clear_and_draw(camera_component, constants, clustered)
	render.set_render_target(render.RENDER_TARGET_DEFAULT)
	render.set_viewport(0, 0, render.get_window_width(), render.get_window_height())
	render.set_camera(camera_component, { use_frustum = true })
	render.clear(state.clear)
	render.set_depth_mask(true)
	render.set_depth_func(graphics.COMPARE_FUNC_LEQUAL)
	render.enable_state(graphics.STATE_DEPTH_TEST)

	if clustered then
		render.enable_state(graphics.STATE_CULL_FACE)
		render.draw(state.opaque, { constants = constants })
		render.disable_state(graphics.STATE_CULL_FACE)
		render.draw(state.mask, { constants = constants })
	end

	-- Standard model materials remain usable while projects migrate individual
	-- material slots to DRP's clustered variants.
	render.enable_state(graphics.STATE_CULL_FACE)
	render.draw(state.model)
	render.disable_state(graphics.STATE_CULL_FACE)

	if clustered then
		render.set_depth_mask(false)
		render.enable_state(graphics.STATE_BLEND)
		render.set_blend_func(
			graphics.BLEND_FACTOR_SRC_ALPHA,
			graphics.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
		)
		render.draw(state.transparent, { constants = constants })
		render.disable_state(graphics.STATE_BLEND)
	end

	render.disable_state(graphics.STATE_DEPTH_TEST)
	render.set_depth_mask(false)
end

function M.initialize(context)
	state.enabled = clustered_requested(context)
	state.render_available = _G.render ~= nil and _G.graphics ~= nil and
		_G.vmath ~= nil and _G.sys ~= nil

	for _, descriptor in ipairs(BUFFER_DESCRIPTORS) do
		local ok, err = resources.declare("clustered." .. descriptor.name, {
			type = "storage_buffer",
			owner = "clustered",
			set = STORAGE_SET,
			binding = descriptor.binding,
		})
		assert(ok, err)
	end

	-- Profile and resource tests run the pipeline outside a Defold render-script
	-- context. The feature contract still registers there, while GPU setup waits
	-- until the actual render runtime is present.
	if not state.render_available then
		return
	end

	state.opaque = render.predicate({ "drp_cluster_opaque" })
	state.mask = render.predicate({ "drp_cluster_mask" })
	state.transparent = render.predicate({ "drp_cluster_transparent" })
	state.model = render.predicate({ "model" })
	state.clear = {
		[graphics.BUFFER_TYPE_COLOR0_BIT] = vmath.vector4(
			sys.get_config_number("render.clear_color_red", 0),
			sys.get_config_number("render.clear_color_green", 0),
			sys.get_config_number("render.clear_color_blue", 0),
			1
		),
		[graphics.BUFFER_TYPE_DEPTH_BIT] = 1,
		[graphics.BUFFER_TYPE_STENCIL_BIT] = 0,
	}
end

function M.on_profile_changed(context)
	local enabled = clustered_requested(context)
	local was_enabled = state.enabled
	state.enabled = enabled
	if not enabled or not state.render_available then
		if was_enabled then
			reset_allocations()
		end
		return
	end
	local viewport = context.viewport
	if viewport then
		configure(context, viewport.width, viewport.height)
	end
end

function M.resize(context, width, height)
	if state.enabled and state.render_available then
		configure(context, width, height)
	end
end

function M.render()
	if not state.render_available then
		return
	end
	local camera_component = active_camera()
	if not camera_component then
		return
	end

	if not state.enabled or not state.available then
		clear_and_draw(camera_component, nil, false)
		return
	end

	bind_cluster_buffers()
	local view = camera.get_view(camera_component)
	local projection = camera.get_projection(camera_component)
	local near_z = math.max(camera.get_near_z(camera_component), 0.0001)
	local far_z = math.max(camera.get_far_z(camera_component), near_z + 0.0001)
	local common, build, depth, assign = make_constants(view, projection, near_z, far_z)

	render_depth_prepass(camera_component)
	build_clusters(build, depth, assign)
	clear_and_draw(camera_component, common, true)
end

function M.finalize()
	reset_allocations()
end

return M
