-- Render the optional debug GUI last, including after HDR and texture views.
-- Its own material tag keeps it independent of scene and application GUI draws.
local M = {}
local predicate

function M.initialize()
	if _G.render and _G.graphics and _G.vmath then
		predicate = render.predicate({ "drp_debug_overlay" })
	end
end

function M.render(context)
	local viewport = context.viewport
	if not predicate or not viewport or viewport.width <= 0 or viewport.height <= 0 then
		return
	end

	render.set_render_target(render.RENDER_TARGET_DEFAULT)
	render.set_viewport(0, 0, viewport.width, viewport.height)
	render.set_camera()
	render.set_view(vmath.matrix4())
	render.set_projection(vmath.matrix4_orthographic(0, viewport.width, 0, viewport.height, -1, 1))
	render.disable_material()
	render.disable_state(graphics.STATE_DEPTH_TEST)
	render.disable_state(graphics.STATE_CULL_FACE)
	render.disable_state(graphics.STATE_STENCIL_TEST)
	render.set_depth_mask(false)
	render.set_color_mask(true, true, true, true)
	render.enable_state(graphics.STATE_BLEND)
	render.set_blend_func(graphics.BLEND_FACTOR_SRC_ALPHA, graphics.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA)
	render.draw(predicate)
	render.disable_state(graphics.STATE_BLEND)
end

function M.finalize()
	predicate = nil
end

return M
