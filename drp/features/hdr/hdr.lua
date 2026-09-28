local resources = require("drp.internal.resources")

local M = { name = "hdr" }

local state = {
	enabled = false,
	available = false,
	render_available = false,
	presenters = {},
	width = 0,
	height = 0,
	exposure = 0,
}

local function release_target()
	if state.target then
		render.set_render_target(render.RENDER_TARGET_DEFAULT)
		render.delete_render_target(state.target)
		state.target = nil
	end
	state.available = false
	state.width, state.height = 0, 0
end

local function finite(value, fallback)
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return fallback
	end
	return value
end

local function unavailable_reason(context, width, height)
	if not state.enabled then return "disabled by profile" end
	if not state.render_available then return "render runtime unavailable" end
	local lighting = context.profile.settings.lighting or {}
	if lighting.cluster_debug == true then return "cluster debug bypass" end
	if not next(state.presenters) then return "HDR presenter not loaded" end
	if width < 1 or height < 1 then return "empty viewport" end
	local caps = context.capabilities or {}
	local supported = (caps.features or {}).float_render_targets
	if supported == false or (caps.strict and supported ~= true) then
		return "floating-point render targets unavailable"
	end
	if not graphics.TEXTURE_FORMAT_RGBA16F then return "RGBA16F unavailable" end
	local limits = caps.limits or {}
	for _, entry in ipairs({
		{ width, limits.max_texture_size_2d }, { height, limits.max_texture_size_2d },
		{ width, limits.max_framebuffer_width }, { height, limits.max_framebuffer_height },
	}) do
		if entry[2] and entry[2] > 0 and entry[1] > entry[2] then
			return "viewport exceeds render-target limits"
		end
	end
end

local function configure(context)
	local settings = context.profile and context.profile.settings or {}
	local rendering = settings.rendering or {}
	state.enabled = rendering.hdr == true
	state.exposure = math.max(-16, math.min(16, finite(rendering.hdr_exposure, 0)))
	local viewport = context.viewport or {}
	local width, height = viewport.width or 0, viewport.height or 0
	state.reason = unavailable_reason(context, width, height)
	if state.reason then
		state.failure = nil
		release_target()
		return
	end
	if context.transition then state.failure = nil end
	if state.failure and state.failure.width == width and state.failure.height == height then
		state.reason = state.failure.reason
		return
	end
	if state.target and state.width == width and state.height == height then return end
	release_target()
	local ok, target = pcall(render.render_target, "drp_hdr_scene", {
		[graphics.BUFFER_TYPE_COLOR0_BIT] = {
			format = graphics.TEXTURE_FORMAT_RGBA16F,
			width = width, height = height,
			min_filter = graphics.TEXTURE_FILTER_LINEAR,
			mag_filter = graphics.TEXTURE_FILTER_LINEAR,
			u_wrap = graphics.TEXTURE_WRAP_CLAMP_TO_EDGE,
			v_wrap = graphics.TEXTURE_WRAP_CLAMP_TO_EDGE,
			flags = render.TEXTURE_BIT,
		},
		[graphics.BUFFER_TYPE_DEPTH_BIT] = {
			format = graphics.TEXTURE_FORMAT_DEPTH,
			width = width, height = height,
		},
	})
	if not ok or not target then
		state.reason = "HDR target allocation failed: " .. tostring(target)
		state.failure = { width = width, height = height, reason = state.reason }
		return
	end
	state.failure = nil
	state.target = target
	state.width, state.height = width, height
	state.available = true
end

function M.initialize()
	assert(resources.declare("hdr.scene", {
		type = "render_target", owner = "hdr", color = "rgba16f", depth = true,
	}))
	state.render_available = _G.render ~= nil and _G.graphics ~= nil and _G.vmath ~= nil
	if state.render_available then
		state.predicate = render.predicate({ "drp_hdr_tonemap" })
		state.constants = render.constant_buffer()
	end
end

function M.begin_frame(context)
	state.scene_rendered = false
	configure(context)
end

-- A mesh is required by render.draw(). Its script announces its lifetime so
-- scenes without the presenter safely retain direct LDR rendering.
function M.on_message(_, message_id, message, sender)
	if message_id == hash("drp_hdr_presenter") then
		state.presenters[tostring(sender)] = message.loaded and true or nil
	end
end

function M.get_render_target()
	return state.available and state.target or render.RENDER_TARGET_DEFAULT
end

function M.output_settings()
	return vmath.vector4(state.available and 1 or 0, 0, 0, 0)
end

function M.scene_rendered()
	state.scene_rendered = true
end

function M.render()
	if not state.available or not state.scene_rendered then return end
	-- This is the sole display conversion. Transparent surfaces have already
	-- blended into the linear scene, before exposure and the nonlinear curve.
	render.set_render_target(render.RENDER_TARGET_DEFAULT)
	render.set_viewport(0, 0, state.width, state.height)
	render.set_camera()
	render.set_view(vmath.matrix4())
	render.set_projection(vmath.matrix4())
	render.disable_state(graphics.STATE_DEPTH_TEST)
	render.disable_state(graphics.STATE_STENCIL_TEST)
	render.disable_state(graphics.STATE_CULL_FACE)
	render.disable_state(graphics.STATE_BLEND)
	render.set_depth_mask(false)
	render.set_color_mask(true, true, true, true)
	state.constants.hdr_settings = vmath.vector4(state.exposure, 0, 0, 0)
	render.enable_texture("texture0", state.target, graphics.BUFFER_TYPE_COLOR0_BIT)
	render.enable_material("drp_hdr_tonemap")
	render.draw(state.predicate, { constants = state.constants })
	render.disable_material()
	render.disable_texture("texture0")
	state.scene_rendered = false
end

function M.get_diagnostics()
	return {
		enabled = state.enabled, available = state.available,
		reason = state.reason, width = state.width, height = state.height,
		exposure = state.exposure, tone_mapper = "aces_fitted",
		color_format = "rgba16f", color_bytes = state.width * state.height * 8,
		presenter_loaded = next(state.presenters) ~= nil,
	}
end

function M.finalize()
	release_target()
	state.enabled = false
	state.scene_rendered = false
	state.render_available = false
	state.failure = nil
	state.predicate, state.constants = nil, nil
end

return M
