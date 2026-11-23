local native = require("drp.internal.native")

local M = {}

local state = {
	render_available = false,
}

function M.initialize()
	state.render_available = _G.render ~= nil and _G.graphics ~= nil
		and _G.vmath ~= nil and _G.sys ~= nil
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

-- The pipeline owns this per-render pass. Features contribute output settings,
-- named textures/constants and storage bindings without owning scene draws.
-- See README.md for the stage order and the lifetime of these fields.
function M.create_pass(context)
	if not state.render_available or not context.camera then
		return nil
	end

	return {
		target = render.RENDER_TARGET_DEFAULT,
		linear_output = false,
		lighting_path = "forward",
		override_model_material = false,
		constants = render.constant_buffer(),
		textures = {},
		storage_buffers = {},
		rendered = false,
	}
end

function M.begin(context, pass)
	local viewport = context.viewport
	local width = viewport and viewport.width or render.get_window_width()
	local height = viewport and viewport.height or render.get_window_height()
	pass.constants.drp_output_settings = vmath.vector4(pass.linear_output and 1 or 0, 0, 0, 0)

	render.set_render_target(pass.target)
	render.set_viewport(0, 0, width, height)
	render.set_camera(context.camera.component, { use_frustum = true })
	render.disable_material()
	-- Depth clears honor the write mask on several backends. The preceding
	-- frame's transparent/fullscreen pass leaves writes disabled.
	render.set_depth_mask(true)
	render.set_color_mask(true, true, true, true)
	render.disable_state(graphics.STATE_BLEND)
	render.disable_state(graphics.STATE_STENCIL_TEST)
	render.clear(state.clear)
	render.set_depth_func(graphics.COMPARE_FUNC_LEQUAL)
	render.enable_state(graphics.STATE_DEPTH_TEST)
end

local function bind_storage_buffers(pass)
	for _, binding in ipairs(pass.storage_buffers) do
		native.bind_storage_buffer(binding.handle, binding.set, binding.binding)
	end
end

local function draw_surface(pass, predicate, material, sort_order)
	if material then
		render.enable_material(material)
	end
	-- Native SSBO binding is immediate; render.draw queues a command. Reapply
	-- the same frame-stable bindings and keep them alive through execution.
	-- Different features must reserve distinct descriptor slots, not reassign
	-- the same slot between queued passes. Texture bindings below are queued.
	bind_storage_buffers(pass)
	render.draw(predicate, { constants = pass.constants, sort_order = sort_order })
	if material then
		render.disable_material()
	end
end

local function draw_models(pass)
	-- Conventional opaque glTF models need the DRP material when scene inputs
	-- require its shading contract. The imported factors/textures stay intact.
	local material
	if pass.linear_output or pass.override_model_material then
		material = "drp_compat_opaque"
	end
	draw_surface(pass, state.model, material, render.SORT_FRONT_TO_BACK)
end

function M.render(context, pass)
	render.disable_material()
	for _, binding in ipairs(pass.textures) do
		render.enable_texture(binding.sampler, binding.target, binding.attachment)
	end

	-- Prepare hooks may record conservative ranges without writing hardware
	-- depth. The shaded opaque/mask passes always establish real visibility.
	render.set_depth_func(graphics.COMPARE_FUNC_LEQUAL)
	render.set_depth_mask(true)
	render.set_color_mask(true, true, true, true)
	render.enable_state(graphics.STATE_DEPTH_TEST)
	render.disable_state(graphics.STATE_BLEND)
	-- glTF's fragment coverage helper enforces the material's doubleSided flag.
	render.disable_state(graphics.STATE_CULL_FACE)

	local clustered = pass.lighting_path == "clustered"
	local opaque_material = not clustered and "drp_compat_opaque" or nil
	local mask_material = not clustered and "drp_compat_mask" or nil
	local transparent_material = not clustered and "drp_compat_transparent" or nil

	-- Retain the established ordering of both lighting paths, including model
	-- materials that use the built-in forward light loop in a clustered scene.
	if not clustered then
		draw_models(pass)
	end
	draw_surface(pass, state.opaque, opaque_material, render.SORT_FRONT_TO_BACK)
	draw_surface(pass, state.mask, mask_material, render.SORT_FRONT_TO_BACK)
	if clustered then
		draw_models(pass)
	end

	render.set_depth_mask(false)
	render.enable_state(graphics.STATE_BLEND)
	render.set_blend_func(graphics.BLEND_FACTOR_SRC_ALPHA, graphics.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA)
	draw_surface(pass, state.transparent, transparent_material, render.SORT_BACK_TO_FRONT)
	render.disable_state(graphics.STATE_BLEND)

	for index = #pass.textures, 1, -1 do
		render.disable_texture(pass.textures[index].sampler)
	end
	render.disable_state(graphics.STATE_DEPTH_TEST)
	render.set_depth_mask(false)
	pass.rendered = true
end

function M.finalize()
	state.render_available = false
	state.opaque, state.mask, state.transparent, state.model, state.clear = nil, nil, nil, nil, nil
end

return M
