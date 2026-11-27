local config = require("drp.features.gtao.config")
local native = require("drp.internal.native")
local resources = require("drp.internal.resources")

local M = { name = "gtao", label = "AO", requirements = { "float_render_targets" } }

local state = {
	settings = config.resolve(),
	render_available = false,
	ready = false,
	produced = false,
	width = 0,
	height = 0,
	raw_width = 0,
	raw_height = 0,
}

local function release_targets()
	if state.depth_target or state.raw_target or state.filtered_target then
		render.set_render_target(render.RENDER_TARGET_DEFAULT)
	end
	for _, key in ipairs({ "depth_target", "raw_target", "filtered_target" }) do
		if state[key] then
			render.delete_render_target(state[key])
			state[key] = nil
		end
	end
	state.ready = false
	state.produced = false
	state.produced_frame, state.produced_far = nil, nil
	state.width, state.height = 0, 0
	state.raw_width, state.raw_height = 0, 0
end

local function dimension(value)
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return 0
	end
	return math.max(0, math.floor(value))
end

local function unavailable_reason(context, width, height)
	if not state.settings.enabled then
		return "disabled by profile"
	end
	if not state.render_available then
		return "render runtime unavailable"
	end
	if not native.is_fullscreen_available() then
		return "native fullscreen rendering is unavailable"
	end
	if context.debug and context.debug.bypass_post then
		return "scene debug view bypass"
	end
	local debug_view = context.debug and context.debug.view
	local explicit_debug_view = debug_view and debug_view ~= "none"
	if not explicit_debug_view and (((context.profile or {}).settings or {}).lighting or {}).cluster_debug == true then
		return "cluster debug bypass"
	end
	if width < 1 or height < 1 then
		return "empty viewport"
	end

	local caps = context.capabilities or {}
	local float_targets = (caps.features or {}).float_render_targets
	if float_targets == false or (caps.strict and float_targets ~= true) then
		return "floating-point render targets unavailable"
	end
	if not graphics.TEXTURE_FORMAT_R32F then
		return "R32F unavailable"
	end

	-- Five glTF material textures plus the filtered visibility texture.
	local limits = caps.limits or {}
	local textures = limits.max_textures_per_stage
	if type(textures) == "number" and textures < 6 then
		return "GTAO requires six textures per shader stage"
	elseif type(textures) ~= "number" and caps.strict then
		return "texture stage limit is unknown"
	end
	for _, limit in ipairs({
		{ width, limits.max_texture_size_2d },
		{ height, limits.max_texture_size_2d },
		{ width, limits.max_framebuffer_width },
		{ height, limits.max_framebuffer_height },
	}) do
		if type(limit[2]) == "number" and limit[2] > 0 and limit[1] > limit[2] then
			return "viewport exceeds render-target limits"
		end
	end
end

local function camera_valid(camera)
	return camera and camera.component and camera.view and camera.projection
		and type(camera.near) == "number" and type(camera.far) == "number"
		and camera.near > 0 and camera.far > camera.near
		and camera.far < math.huge
end

local function create_target(name, width, height, format, depth)
	local attachments = {
		[graphics.BUFFER_TYPE_COLOR0_BIT] = {
			format = format,
			width = width,
			height = height,
			min_filter = graphics.TEXTURE_FILTER_NEAREST,
			mag_filter = graphics.TEXTURE_FILTER_NEAREST,
			u_wrap = graphics.TEXTURE_WRAP_CLAMP_TO_EDGE,
			v_wrap = graphics.TEXTURE_WRAP_CLAMP_TO_EDGE,
			flags = render.TEXTURE_BIT,
		},
	}
	if depth then
		attachments[graphics.BUFFER_TYPE_DEPTH_BIT] = {
			format = graphics.TEXTURE_FORMAT_DEPTH,
			width = width,
			height = height,
		}
	end
	local ok, target = pcall(render.render_target, name, attachments)
	if not ok or not target then
		return nil, tostring(target)
	end
	return target
end

local function configure(context)
	state.ready = false
	state.settings = config.resolve(((context.profile or {}).settings or {}).post)
	if context.transition then
		state.failure = nil
	end
	local viewport = context.viewport or {}
	local width, height = dimension(viewport.width), dimension(viewport.height)
	state.reason = unavailable_reason(context, width, height)
	if state.reason then
		state.failure = nil
		release_targets()
		return
	end

	-- No camera means no valid screen-space data this frame. Keep allocations
	-- so temporarily disabling a camera does not churn GPU resources.
	if not camera_valid(context.camera) then
		state.reason = "no camera with a positive depth range"
		return
	end
	local raw_width = math.max(1, math.ceil(width * state.settings.resolution))
	local raw_height = math.max(1, math.ceil(height * state.settings.resolution))
	local signature = table.concat({ width, height, raw_width, raw_height }, "x")
	if state.failure and state.failure.signature == signature then
		state.reason = state.failure.reason
		return
	end
	if state.depth_target and state.width == width and state.height == height
		and state.raw_width == raw_width and state.raw_height == raw_height then
		state.ready = true
		return
	end

	release_targets()
	local err
	state.depth_target, err = create_target("drp_gtao_depth", width, height,
		graphics.TEXTURE_FORMAT_R32F, true)
	if state.depth_target then
		state.raw_target, err = create_target("drp_gtao_raw", raw_width, raw_height,
			graphics.TEXTURE_FORMAT_RGBA, false)
	end
	if state.raw_target then
		state.filtered_target, err = create_target("drp_gtao_filtered", width, height,
			graphics.TEXTURE_FORMAT_RGBA, false)
	end
	if not state.filtered_target then
		release_targets()
		state.reason = "GTAO target allocation failed: " .. tostring(err)
		state.failure = { signature = signature, reason = state.reason }
		return
	end
	state.failure = nil
	state.width, state.height = width, height
	state.raw_width, state.raw_height = raw_width, raw_height
	state.ready = true
end

function M.initialize()
	assert(resources.declare("gtao.depth", {
		type = "render_target", owner = "gtao", color = "r32f", depth = true,
	}))
	assert(resources.declare("gtao.raw", {
		type = "render_target", owner = "gtao", color = "rgba8",
	}))
	assert(resources.declare("gtao.filtered", {
		type = "render_target", owner = "gtao", color = "rgba8",
	}))
	state.render_available = _G.render ~= nil and _G.graphics ~= nil and _G.vmath ~= nil
	if state.render_available then
		state.opaque = render.predicate({ "drp_cluster_opaque" })
		state.mask = render.predicate({ "drp_cluster_mask" })
		state.model = render.predicate({ "model" })
		state.ao = render.predicate({ "drp_gtao" })
		state.blur = render.predicate({ "drp_gtao_blur" })
		state.constants = render.constant_buffer()
		state.clear = {
			[graphics.BUFFER_TYPE_COLOR0_BIT] = vmath.vector4(0),
			[graphics.BUFFER_TYPE_DEPTH_BIT] = 1,
		}
	end
end

function M.begin_frame(context)
	state.produced = false
	state.produced_frame, state.produced_far = nil, nil
	configure(context)
	if not state.ready then
		return
	end

	-- Both native entries must exist before the first render.draw builds the
	-- render list. A failed submission disables AO without affecting lighting.
	for _, path in ipairs({
		"/drp/features/gtao/gtao.materialc",
		"/drp/features/gtao/blur.materialc",
	}) do
		local submitted, err = native.submit_fullscreen(path)
		if not submitted then
			state.reason = "GTAO fullscreen submission failed: " .. tostring(err)
			state.ready = false
			return
		end
	end
end

local function render_depth(camera)
	render.set_render_target(state.depth_target)
	render.set_viewport(0, 0, state.width, state.height)
	render.set_camera(camera.component, { use_frustum = true })
	render.disable_state(graphics.STATE_STENCIL_TEST)
	render.disable_state(graphics.STATE_BLEND)
	render.disable_state(graphics.STATE_CULL_FACE)
	render.enable_state(graphics.STATE_DEPTH_TEST)
	render.set_depth_func(graphics.COMPARE_FUNC_LEQUAL)
	render.set_depth_mask(true)
	render.set_color_mask(true, true, true, true)
	render.clear(state.clear)

	-- The glTF coverage test preserves alpha cutoff and double-sided materials.
	-- Transparent surfaces do not belong in a single-layer depth representation.
	render.enable_material("drp_gtao_depth_opaque")
	render.draw(state.opaque, { sort_order = render.SORT_FRONT_TO_BACK })
	render.draw(state.model, { sort_order = render.SORT_FRONT_TO_BACK })
	render.enable_material("drp_gtao_depth_mask")
	render.draw(state.mask, { sort_order = render.SORT_FRONT_TO_BACK })
	render.disable_material()
end

local function prepare_fullscreen()
	render.set_camera()
	render.set_view(vmath.matrix4())
	render.set_projection(vmath.matrix4())
	render.disable_state(graphics.STATE_DEPTH_TEST)
	render.disable_state(graphics.STATE_STENCIL_TEST)
	render.disable_state(graphics.STATE_CULL_FACE)
	render.disable_state(graphics.STATE_BLEND)
	render.set_depth_mask(false)
	render.set_color_mask(true, true, true, true)
end

function M.render_before_scene(context)
	if not state.ready then
		return
	end
	local settings = state.settings
	local constants = state.constants
	constants.gtao_inverse_projection = vmath.inv(context.camera.projection)
	constants.gtao_projection = context.camera.projection
	constants.gtao_depth_size = vmath.vector4(state.width, state.height,
		1 / state.width, 1 / state.height)
	constants.gtao_target_size = vmath.vector4(state.raw_width, state.raw_height,
		1 / state.raw_width, 1 / state.raw_height)
	constants.gtao_settings = vmath.vector4(settings.radius, settings.intensity,
		settings.power, settings.bias)
	constants.gtao_quality = vmath.vector4(settings.slices, settings.steps, 0.5, 128)
	constants.gtao_filter_settings = vmath.vector4(settings.radius, 8, 0, 0)

	render_depth(context.camera)
	prepare_fullscreen()
	render.set_render_target(state.raw_target)
	render.set_viewport(0, 0, state.raw_width, state.raw_height)
	render.enable_texture("drp_scene_depth", state.depth_target, graphics.BUFFER_TYPE_COLOR0_BIT)
	render.enable_material("drp_gtao")
	render.draw(state.ao, { constants = constants })
	render.disable_material()

	-- Resolve to scene resolution before shading. Depth-aware weights keep
	-- coarse AO samples from bleeding across foreground/background boundaries.
	render.set_render_target(state.filtered_target)
	render.set_viewport(0, 0, state.width, state.height)
	render.enable_texture("drp_gtao_raw", state.raw_target, graphics.BUFFER_TYPE_COLOR0_BIT)
	render.enable_material("drp_gtao_blur")
	render.draw(state.blur, { constants = constants })
	render.disable_material()
	render.disable_texture("drp_gtao_raw")
	render.disable_texture("drp_scene_depth")
	render.set_render_target(render.RENDER_TARGET_DEFAULT)
	state.produced = true
	state.produced_frame = context.frame
	state.produced_far = context.camera.far
end

function M.configure_scene(context, pass)
	-- Every scene gets explicit neutral constants when this frame has no AO.
	-- The shared renderer owns binding lifetime and the conventional model
	-- material override; GTAO only contributes its produced scene input.
	pass.constants.drp_ao_projection = context.camera.projection
	pass.constants.drp_ao_settings = vmath.vector4(0)
	if not state.produced then
		return
	end

	pass.constants.drp_ao_settings = vmath.vector4(1, 1 / state.width, 1 / state.height, 0)
	pass.textures[#pass.textures + 1] = {
		sampler = "drp_ao_texture",
		target = state.filtered_target,
		attachment = graphics.BUFFER_TYPE_COLOR0_BIT,
	}
	pass.override_model_material = true
end

function M.get_properties()
	return {
		{
			id = "enabled", type = "boolean",
			ui = { label = "Enabled" },
			diagnostic_key = "enabled",
			path = "post.gtao", default = false,
		},
		{
			id = "radius", type = "number",
			ui = { label = "Radius", min = 0.01, max = 10, step = 0.01, scale = "log" },
			diagnostic_key = "radius",
			path = "post.gtao_radius", default = 0.5,
			limits = { min = 0.001, max = 1000000 },
		},
		{
			id = "intensity", type = "number",
			ui = { label = "Intensity", min = 0, max = 4, step = 0.1 },
			diagnostic_key = "intensity",
			path = "post.gtao_intensity", default = 1,
			limits = { min = 0, max = 4 },
		},
		{
			id = "power", type = "number",
			ui = { label = "Power", min = 0.1, max = 4, step = 0.1 },
			diagnostic_key = "power",
			path = "post.gtao_power", default = 1,
			limits = { min = 0.1, max = 4 },
		},
		{
			id = "bias", type = "number",
			ui = { label = "Bias", min = 0, max = 0.25, step = 0.005 },
			diagnostic_key = "bias",
			path = "post.gtao_bias", default = 0.02,
			limits = { min = 0, max = 0.25 },
		},
		{
			id = "quality", type = "enum",
			ui = { label = "Quality" },
			diagnostic_key = "quality",
			path = "post.gtao_quality", default = "medium",
			options = { "low", "medium", "high", "ultra" },
		},
		{
			id = "resolution", type = "number",
			ui = { label = "Resolution scale", min = 0.25, max = 1, step = 0.25 },
			diagnostic_key = "resolution",
			path = "post.gtao_resolution", default = 0.5,
			limits = { min = 0.25, max = 1 },
		},
	}
end

function M.get_debug_views()
	return {
		{
			id = "gtao.filtered",
			label = "AO",
			description = "Filtered ambient visibility: white is unoccluded, dark is occluded.",
			kind = "texture",
		},
		{
			id = "gtao.raw",
			label = "Raw AO",
			description = "Ambient visibility before the depth-aware filter and upsampling.",
			kind = "texture",
		},
		{
			id = "gtao.depth",
			label = "Scene depth",
			description = "Logarithmic view-space depth used to reconstruct AO geometry.",
			kind = "texture",
		},
	}
end

function M.get_debug_source(context, id)
	local target
	local width, height = state.width, state.height
	local mode = "visibility"
	if id == "gtao.filtered" then
		target = state.filtered_target
	elseif id == "gtao.raw" then
		target = state.raw_target
		width, height = state.raw_width, state.raw_height
	elseif id == "gtao.depth" then
		target = state.depth_target
		mode = "depth"
	else
		return nil, "unknown GTAO debug view"
	end

	-- Allocations may survive camera loss or a failed fullscreen submission.
	-- Only expose targets filled during this frame, never their old contents.
	if not state.produced or state.produced_frame ~= context.frame or not target then
		return nil, state.reason or "GTAO was not rendered this frame"
	end
	return {
		target = target,
		attachment = graphics.BUFFER_TYPE_COLOR0_BIT,
		width = width,
		height = height,
		mode = mode,
		far = state.produced_far,
	}
end

function M.get_diagnostics()
	return {
		enabled = state.settings.enabled,
		available = state.produced,
		reason = state.reason,
		width = state.width,
		height = state.height,
		raw_width = state.raw_width,
		raw_height = state.raw_height,
		quality = state.settings.quality,
		resolution = state.settings.resolution,
		radius = state.settings.radius,
		intensity = state.settings.intensity,
		power = state.settings.power,
		bias = state.settings.bias,
		slices = state.settings.slices,
		steps = state.settings.steps,
		temporal = false,
		depth_format = "r32f",
		ao_format = "rgba8",
		-- Includes an estimated four bytes/pixel for the hardware depth attachment.
		estimated_target_bytes = state.width * state.height * 12
			+ state.raw_width * state.raw_height * 4,
	}
end

function M.finalize()
	release_targets()
	state.settings = config.resolve()
	state.render_available = false
	state.failure, state.reason = nil, nil
	state.opaque, state.mask, state.model = nil, nil, nil
	state.ao, state.blur, state.constants, state.clear = nil, nil, nil, nil
	resources.remove("gtao.depth")
	resources.remove("gtao.raw")
	resources.remove("gtao.filtered")
end

return M
