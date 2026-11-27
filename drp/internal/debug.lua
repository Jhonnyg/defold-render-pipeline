local features = require("drp.internal.features")
local native = require("drp.internal.native")
local utils = require("drp.internal.utils")

local M = {}

local state = {
	view = "none",
	render_available = false,
}

local function find_view(id)
	for _, view in ipairs(M.get_views()) do
		if view.id == id then
			return view
		end
	end
end

local function positive(value)
	return type(value) == "number" and value > 0 and value < math.huge
end

local function frame_unavailable_reason(context)
	local viewport = context.viewport or {}
	if not positive(viewport.width) or not positive(viewport.height) then
		return "empty viewport"
	end
	local camera = context.camera
	if not camera or not camera.component or not camera.view or not camera.projection then
		return "no active scene camera"
	end
end

function M.get_views()
	local views = {
		{
			id = "none",
			label = "Scene",
			description = "Normal scene rendering.",
			kind = "scene",
		},
	}
	for _, view in ipairs(features.get_debug_views()) do
		views[#views + 1] = view
	end
	return views
end

function M.set_view(id)
	if id == nil then
		id = "none"
	end
	if type(id) ~= "string" or not find_view(id) then
		return nil, "unknown debug view '" .. tostring(id) .. "'"
	end
	if state.view ~= id then
		state.context = nil
	end
	state.view = id
	return true
end

function M.initialize()
	state.render_available = _G.render ~= nil and _G.graphics ~= nil and _G.vmath ~= nil
	if state.render_available then
		state.predicate = render.predicate({ "drp_debug_view" })
		state.constants = render.constant_buffer()
	end
end

function M.begin_frame(context)
	-- Snapshot before feature begin_frame: scene debug modes can bypass post
	-- processing, and texture debug submissions must precede the first draw.
	local selected = find_view(state.view)
	local debug = {
		view = selected.id,
		label = selected.label,
		description = selected.description,
		feature = selected.feature,
		kind = selected.kind,
		bypass_post = selected.kind == "scene" and selected.id ~= "none",
		available = selected.id == "none",
	}
	context.debug = debug
	state.context = context
	if debug.view == "none" then
		return
	end

	debug.reason = frame_unavailable_reason(context)
	if debug.reason then
		return
	end
	if not state.render_available then
		debug.reason = "render runtime unavailable"
		return
	end
	if debug.kind == "texture" then
		local submitted, err = native.submit_fullscreen("/drp/debug/view.materialc")
		if not submitted then
			debug.reason = "debug fullscreen submission failed: " .. tostring(err)
			return
		end
		debug.submitted = true
	end
	debug.reason = "waiting for this frame's debug source"
end

function M.render(context)
	local debug = context.debug
	if not debug or debug.view == "none" or debug.presented then
		return
	end
	if not state.render_available or frame_unavailable_reason(context) then
		return
	end
	if debug.kind == "texture" and not debug.submitted then
		return
	end

	-- Sources belong to their features. Query only after the frame's scene and
	-- post passes have completed; never cache a target across resize or disable.
	local source, reason = features.get_debug_source(context, debug.view)
	if not source then
		debug.reason = reason or "debug source was not produced this frame"
		return
	end
	if debug.kind == "scene" then
		debug.available = true
		debug.reason = nil
		debug.presented = true
		debug.width, debug.height = source.width, source.height
		return
	end
	if not source.target or not source.attachment
		or not positive(source.width) or not positive(source.height) then
		debug.reason = "invalid debug texture source"
		return
	end
	if source.mode ~= "visibility" and source.mode ~= "depth" then
		debug.reason = "unsupported debug texture mode"
		return
	end
	if source.mode == "depth" and not positive(source.far) then
		debug.reason = "debug depth source has no positive far plane"
		return
	end

	local viewport = context.viewport
	render.set_render_target(render.RENDER_TARGET_DEFAULT)
	render.set_viewport(0, 0, viewport.width, viewport.height)
	render.set_camera()
	render.set_view(vmath.matrix4())
	render.set_projection(vmath.matrix4())
	render.disable_state(graphics.STATE_DEPTH_TEST)
	render.disable_state(graphics.STATE_STENCIL_TEST)
	render.disable_state(graphics.STATE_CULL_FACE)
	render.disable_state(graphics.STATE_BLEND)
	render.set_depth_mask(false)
	render.set_color_mask(true, true, true, true)
	state.constants.drp_debug_settings = vmath.vector4(
		source.mode == "depth" and 1 or 0, source.far or 1, 0, 0)
	render.enable_texture("drp_debug_texture", source.target, source.attachment)
	render.enable_material("drp_debug_view")
	render.draw(state.predicate, { constants = state.constants })
	render.disable_material()
	render.disable_texture("drp_debug_texture")
	debug.available = true
	debug.reason = nil
	debug.presented = true
	debug.width, debug.height = source.width, source.height
end

function M.get_state(context)
	local selected = find_view(state.view)
	local result = {
		view = selected.id,
		label = selected.label,
		description = selected.description,
		feature = selected.feature,
		kind = selected.kind,
		available = selected.id == "none",
	}
	context = context or state.context
	local debug = context and context.debug
	if debug and debug.view == state.view then
		result.available = debug.available
		result.reason = debug.reason
		result.width, result.height = debug.width, debug.height
	elseif not result.available then
		result.reason = "waiting for the next rendered frame"
	end
	return utils.copy(result)
end

function M.finalize()
	-- The native bridge owns cached fullscreen materials. Features own targets;
	-- debug only borrows them while drawing and has no resize-time allocations.
	state.view = "none"
	state.context = nil
	state.render_available = false
	state.predicate, state.constants = nil, nil
end

return M
