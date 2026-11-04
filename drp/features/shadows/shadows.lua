local utils = require("drp.internal.utils")
local native = require("drp.internal.native")
local config = require("drp.features.shadows.config")
local atlas = require("drp.features.shadows.atlas")
local views = require("drp.features.shadows.views")

local M = { name = "shadows" }
local state = {
	initialized = false,
	enabled = false,
	available = false,
	settings = {},
	reason = "not initialized",
	cache = {},
}
local ZERO_DATA = string.rep("\0", config.buffer_floats * 4)

local function release_atlases()
	if state.local_target then
		render.delete_render_target(state.local_target)
	end
	if state.directional_target then
		render.delete_render_target(state.directional_target)
	end
	state.local_target, state.directional_target, state.allocation_key = nil, nil, nil
	state.cache = {}
end

local function target(name, size)
	return render.render_target(name, {
		[graphics.BUFFER_TYPE_COLOR0_BIT] = {
			format = graphics.TEXTURE_FORMAT_R32F or graphics.TEXTURE_FORMAT_RGBA32F,
			width = size,
			height = size,
			min_filter = graphics.TEXTURE_FILTER_NEAREST,
			mag_filter = graphics.TEXTURE_FILTER_NEAREST,
			u_wrap = graphics.TEXTURE_WRAP_CLAMP_TO_EDGE,
			v_wrap = graphics.TEXTURE_WRAP_CLAMP_TO_EDGE,
			flags = render.TEXTURE_BIT,
		},
		[graphics.BUFFER_TYPE_DEPTH_BIT] = {
			format = graphics.TEXTURE_FORMAT_DEPTH,
			width = size,
			height = size,
		},
	})
end

local function configure(context)
	state.settings = utils.copy((context.profile and context.profile.settings or {}).shadows or {})
	state.config = config.resolve(state.settings, (context.capabilities or {}).limits)
	state.enabled, state.available = state.config.enabled, false
	state.reason = nil

	local settings = context.profile and context.profile.settings or {}
	local capabilities = context.capabilities or {}
	local caps = capabilities.features or {}
	local limits = capabilities.limits or {}

	-- Keep the first failed prerequisite so diagnostics explain why no maps render.
	if not state.enabled then
		state.reason = "disabled by settings"
	elseif not _G.render or not _G.graphics or not _G.vmath then
		state.reason = "render runtime unavailable"
	elseif (settings.rendering or {}).path ~= "forward_plus" then
		state.reason = "requires clustered rendering"
	elseif not native.is_shadows_available() then
		state.reason = "native light API unavailable"
	elseif (not graphics.TEXTURE_FORMAT_R32F and not graphics.TEXTURE_FORMAT_RGBA32F) or caps.float_render_targets == false then
		state.reason = "floating-point render targets unavailable"
	elseif caps.storage_buffers == false then
		state.reason = "storage buffers unavailable"
	elseif (limits.max_samplers_per_stage and limits.max_samplers_per_stage > 0 and limits.max_samplers_per_stage < 7)
		or (limits.max_textures_per_stage and limits.max_textures_per_stage > 0 and limits.max_textures_per_stage < 7) then
		state.reason = "seven fragment textures required"
	elseif limits.max_storage_buffer_range and limits.max_storage_buffer_range > 0 and limits.max_storage_buffer_range < #ZERO_DATA then
		state.reason = "shadow metadata exceeds storage-buffer limit"
	end

	if state.reason then
		release_atlases()
	end

	-- Forward-only materials do not declare the shadow SSBO or fallback sampler.
	if (settings.rendering or {}).path ~= "forward_plus" then
		if state.fallback then
			render.delete_render_target(state.fallback)
			state.fallback = nil
		end
		if state.buffer then
			native.unbind_storage_buffer(state.buffer)
			native.delete_storage_buffer(state.buffer)
			state.buffer = nil
		end
	end
end

function M.initialize(context)
	state.initialized = true
	configure(context)
end

function M.on_profile_changed(context)
	configure(context)
end

-- Declared shader resources must remain valid even when shadowing is disabled.
-- Called only for the clustered path; legacy exports never allocate these.
function M.prepare_scene()
	if state.buffer and state.fallback then
		return true
	end
	local ok, err = pcall(function()
		if not state.buffer then
			state.buffer = native.create_storage_buffer(#ZERO_DATA, native.BUFFER_USAGE_DYNAMIC_DRAW, ZERO_DATA)
		end
		if not state.fallback then
			state.fallback = render.render_target("drp_shadow_fallback", {
				[graphics.BUFFER_TYPE_COLOR0_BIT] = {
					format = graphics.TEXTURE_FORMAT_RGBA,
					width = 1,
					height = 1,
					min_filter = graphics.TEXTURE_FILTER_NEAREST,
					mag_filter = graphics.TEXTURE_FILTER_NEAREST,
					u_wrap = graphics.TEXTURE_WRAP_CLAMP_TO_EDGE,
					v_wrap = graphics.TEXTURE_WRAP_CLAMP_TO_EDGE,
					flags = render.TEXTURE_BIT,
				},
			})
			render.set_render_target(state.fallback)
			render.set_color_mask(true, true, true, true)
			render.clear({ [graphics.BUFFER_TYPE_COLOR0_BIT] = vmath.vector4(1, 1, 1, 1) })
			render.set_render_target(render.RENDER_TARGET_DEFAULT)
		end
	end)
	if not ok then
		state.failure = "shadow resource allocation failed: " .. tostring(err)
	end
	return ok and state.buffer ~= nil and state.fallback ~= nil
end

local function allocate()
	local budgets = state.config
	local key = table.concat({ budgets.atlas_size, budgets.tile_size, budgets.directional_atlas_size, budgets.directional_tile_size }, ":")
	if key == state.allocation_key then
		return
	end
	release_atlases()
	state.local_target = assert(target("drp_shadow_local", budgets.atlas_size))
	state.directional_target = assert(target("drp_shadow_directional", budgets.directional_atlas_size))
	state.local_atlas, state.directional_atlas = atlas.new(budgets.local_capacity), atlas.new(budgets.directional_capacity)
	state.allocation_key = key
	state.clear_predicate = state.clear_predicate or render.predicate({ "drp_shadow_clear" })
	state.opaque = state.opaque or render.predicate({ "drp_cluster_opaque" })
	state.mask = state.mask or render.predicate({ "drp_cluster_mask" })
	state.models = state.models or render.predicate({ "model" })
end

local function restore(context)
	render.disable_material()
	render.set_render_target(render.RENDER_TARGET_DEFAULT)
	local viewport = context.viewport or {}
	render.set_viewport(0, 0, viewport.width or render.get_window_width(), viewport.height or render.get_window_height())
	render.set_camera(context.camera and context.camera.component or nil, { use_frustum = true })
	render.set_depth_func(graphics.COMPARE_FUNC_LEQUAL)
	render.set_depth_mask(true)
	render.set_color_mask(true, true, true, true)
	render.enable_state(graphics.STATE_DEPTH_TEST)
	render.enable_state(graphics.STATE_CULL_FACE)
	render.disable_state(graphics.STATE_BLEND)
end

local function draw_view(item, tile, target_handle, size, tile_size)
	local x, y = atlas.viewport(tile, size, tile_size)
	render.set_render_target(target_handle)
	render.set_camera()
	render.disable_state(graphics.STATE_BLEND)
	render.disable_state(graphics.STATE_STENCIL_TEST)
	render.set_color_mask(true, true, true, true)
	render.enable_state(graphics.STATE_DEPTH_TEST)
	render.set_depth_mask(true)

	-- render.clear clears the entire attachment. A far-depth fullscreen triangle
	-- clears only this viewport, preserving every other cached tile.
	render.set_viewport(x, y, tile_size, tile_size)
	render.set_view(vmath.matrix4())
	render.set_projection(vmath.matrix4())
	render.set_depth_func(graphics.COMPARE_FUNC_ALWAYS)
	render.disable_state(graphics.STATE_CULL_FACE)
	render.enable_material("drp_shadow_clear")
	render.draw(state.clear_predicate)
	render.disable_material()

	-- One cleared border texel prevents neighbor leakage from clamped filter taps.
	render.set_viewport(x + 1, y + 1, tile_size - 2, tile_size - 2)
	render.set_view(item.view)
	render.set_projection(item.projection)
	render.set_depth_func(graphics.COMPARE_FUNC_LEQUAL)
	-- Match glTF sidedness in the visible pass, including double-sided opaque.
	render.disable_state(graphics.STATE_CULL_FACE)
	render.enable_material("drp_shadow_opaque")
	local options = {
		frustum = item.matrix,
		frustum_planes = render.FRUSTUM_PLANES_ALL,
		sort_order = render.SORT_FRONT_TO_BACK,
	}
	render.draw(state.opaque, options)
	render.draw(state.models, options)
	render.disable_state(graphics.STATE_CULL_FACE)
	render.enable_material("drp_shadow_mask")
	render.draw(state.mask, options)
	render.disable_material()
end

local function write(data, offset, ...)
	for i = 1, select("#", ...) do
		data[offset + i] = select(i, ...)
	end
end

local function publish(data, light, items, tiles, splits, next_view, size, tile_size)
	-- Headers use the current engine buffer index. Views are packed after all
	-- headers, with column-major matrices matching the GLSL metadata layout.
	local offset = light.index * config.header_floats
	write(data, offset, light.type, next_view, #items, light.softness,
		light.bias, light.normal_bias, state.config.cascade_blend, state.config.level,
		splits and splits[1] or 0, splits and splits[2] or 0, splits and splits[3] or 0, splits and splits[4] or 0)

	for i, item in ipairs(items) do
		local base = config.light_capacity * config.header_floats + (next_view + i - 1) * config.view_floats
		for column = 0, 3 do
			for row = 0, 3 do
				data[base + column * 4 + row + 1] = item.matrix["m" .. row .. column]
			end
		end
		local x, y = atlas.viewport(tiles[i], size, tile_size)
		write(data, base + 16, (x + 1) / size, (y + 1) / size, (tile_size - 2) / size, 1 / size,
			item.near, item.far, state.config.distance, 0)
	end
	return next_view + #items
end

local function render_maps(context)
	local lights, scene_revision = native.get_shadow_lights()
	state.registered = #lights
	if #lights == 0 then
		release_atlases()
		state.failure = nil
		state.frame_reason = "no active shadow lights"
		return
	end

	allocate()
	assert(native.submit_fullscreen("/drp/features/shadows/clear.materialc"), "shadow tile-clear submission failed")

	-- Stable priority and registration order determine residency. Index order is
	-- deliberately irrelevant; the engine is free to compact the light buffer.
	table.sort(lights, function(a, b)
		return a.priority == b.priority and a.id < b.id or a.priority > b.priority
	end)

	local selected = {}
	local local_selected = {}
	local directional_selected = {}
	local jobs = {}
	local local_count = 0
	local directional_count = 0
	local local_views = 0
	local directional_views = 0
	local budgets = state.config

	-- Reserve complete light projections before spending this frame's update
	-- budget. Point lights require all six faces; partial residency is unusable.
	for _, light in ipairs(lights) do
		if light.index >= 0 and light.index < config.light_capacity then
			local directional = light.type == 0
			local count = directional and budgets.directional_cascades or (light.type == 1 and 6 or 1)
			local admitted = directional
				and directional_count < budgets.max_shadowed_directional_lights
				and directional_views + count <= budgets.directional_capacity
				or not directional
				and local_count < budgets.max_shadowed_local_lights
				and local_views + count <= budgets.local_capacity
			if admitted then
				local items, splits
				if directional then
					items, splits = views.directional(light, context.camera, budgets)
				else
					items = views.local_light(light, budgets)
				end
				if items then
					selected[light.id] = true
					if directional then
						directional_selected[light.id] = true
					else
						local_selected[light.id] = true
					end

					jobs[#jobs + 1] = {
						light = light,
						items = items,
						splits = splits,
						directional = directional,
					}

					if directional then
						directional_count, directional_views = directional_count + 1, directional_views + count
					else
						local_count, local_views = local_count + 1, local_views + count
					end
				end
			end
		end
	end

	-- Release residency and cached transforms for lights no longer selected.
	atlas.retain(state.local_atlas, local_selected)
	atlas.retain(state.directional_atlas, directional_selected)
	for id in pairs(state.cache) do
		if not selected[id] then
			state.cache[id] = nil
		end
	end

	-- Equal-priority dynamic lights take turns when the update budget is limited.
	table.sort(jobs, function(a, b)
		if a.light.priority ~= b.light.priority then
			return a.light.priority > b.light.priority
		end
		local af, bf = (state.cache[a.light.id] or {}).frame or -1, (state.cache[b.light.id] or {}).frame or -1
		return af == bf and a.light.id < b.light.id or af < bf
	end)

	-- Zero headers leave deferred or dropped lights explicitly unshadowed.
	local data = {}
	for i = 1, config.buffer_floats do
		data[i] = 0
	end

	local next_view = 0
	for _, job in ipairs(jobs) do
		local light, items = job.light, job.items
		local pool = job.directional and state.directional_atlas or state.local_atlas
		local size = job.directional and budgets.directional_atlas_size or budgets.atlas_size
		local tile_size = job.directional and budgets.directional_tile_size or budgets.tile_size
		local tiles = atlas.allocate(pool, light.id, #items)
		local signature = views.signature(items, scene_revision)
		local cache = state.cache[light.id]
		local valid = tiles and light.cache and cache and cache.signature == signature
		if valid then
			state.cache_hits = state.cache_hits + #items
		end

		-- Cache validity depends on projection and geometry, never buffer order.
		if tiles and not valid and state.updated_views + #items <= budgets.max_updates_per_frame then
			for i, item in ipairs(items) do
				draw_view(item, tiles[i], job.directional and state.directional_target or state.local_target, size, tile_size)
			end
			state.updated_views = state.updated_views + #items
			state.cache[light.id] = { signature = signature, frame = context.frame or 0 }
			valid = true
		end

		if valid then
			next_view = publish(data, light, items, tiles, job.splits, next_view, size, tile_size)
			state.shadowed_lights = state.shadowed_lights + 1
		else
			-- Never sample a previous pose merely because this frame ran out of work.
			state.deferred_views = state.deferred_views + #items
		end
	end

	state.dropped_lights = #lights - #jobs
	assert(native.update_storage_buffer(state.buffer, 0, native.pack_floats(data)))
	state.available, state.failure = true, nil
end

function M.render(context)
	state.available = false
	state.frame_reason = nil
	state.registered = 0
	state.updated_views = 0
	state.cache_hits = 0
	state.shadowed_lights = 0
	state.deferred_views = 0
	state.dropped_lights = 0

	if state.reason then
		return
	end
	if not context.camera or context.camera.near <= 0 then
		state.frame_reason = "requires an active camera with positive clip depths"
		return
	end
	if not M.prepare_scene() then
		return
	end

	-- A failed draw must restore scene state and invalidate any partially
	-- written maps before the clustered/HDR pass runs.
	local ok, err = pcall(render_maps, context)
	restore(context)
	if not ok then
		state.available = false
		state.failure = "shadow rendering failed: " .. tostring(err)
		state.cache = {}
		if state.last_failure ~= state.failure then
			print("DRP " .. state.failure)
			state.last_failure = state.failure
		end
	end
end

function M.bind_scene(constants)
	constants.drp_shadow_settings = vmath.vector4(state.available and 1 or 0, 0, 0, 0)
	native.bind_storage_buffer(state.buffer, 2, 6)
	render.enable_texture("drp_shadow_local", state.available and state.local_target or state.fallback, graphics.BUFFER_TYPE_COLOR0_BIT)
	render.enable_texture("drp_shadow_directional", state.available and state.directional_target or state.fallback, graphics.BUFFER_TYPE_COLOR0_BIT)
end

function M.unbind_scene()
	render.disable_texture("drp_shadow_local")
	render.disable_texture("drp_shadow_directional")
	-- Native SSBO binding is immediate; render.draw is queued until Lua returns.
	-- Keep binding 6 alive through command playback, like the cluster buffers.
	-- It is unbound on resource teardown, after this frame's draws have finished.
end

function M.get_diagnostics()
	return {
		initialized = state.initialized,
		enabled = state.enabled,
		available = state.available,
		effective_quality = state.available and state.config.quality or "off",
		reason = state.reason or state.failure or state.frame_reason,
		settings = utils.copy(state.settings),
		budgets = utils.copy(state.config or {}),
		registered_lights = state.registered or 0,
		shadowed_lights = state.shadowed_lights or 0,
		updated_views = state.updated_views or 0,
		cached_views = state.cache_hits or 0,
		deferred_views = state.deferred_views or 0,
		dropped_lights = state.dropped_lights or 0,
		atlas_bytes = state.local_target
			and (state.config.atlas_size^2 + state.config.directional_atlas_size^2)
				* (graphics.TEXTURE_FORMAT_R32F and 8 or 20)
			or 0,
	}
end

function M.finalize()
	release_atlases()
	if state.fallback then
		render.delete_render_target(state.fallback)
	end
	if state.buffer and native.is_available() then
		native.unbind_storage_buffer(state.buffer)
		native.delete_storage_buffer(state.buffer)
	end
	state = {
		initialized = false,
		enabled = false,
		available = false,
		settings = {},
		reason = "not initialized",
		cache = {},
	}
end

return M
