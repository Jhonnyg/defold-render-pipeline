local M = {}
local drp = require("drp.drp")
local pipeline = require("drp.internal.pipeline")
local shadows = require("drp.features.shadows.shadows")
local config = require("drp.features.shadows.config")
local atlas = require("drp.features.shadows.atlas")
local views = require("drp.features.shadows.views")

-- Verifies frame-boundary overrides, defensive diagnostics and compatibility fallback.
local function settings_lifecycle()
	pipeline.finalize()
	assert(drp.initialize({ quality = "balanced", platform = "html5",
		capabilities = { features = { compute_shaders = true, storage_buffers = true } } }))
	local info = shadows.get_diagnostics()
	assert(info.initialized and info.enabled and not info.available)
	assert(info.reason == "render runtime unavailable")
	assert(info.settings.quality == "pcf" and info.settings.max_shadowed_local_lights == 2)
	info.settings.quality = "mutated"
	assert(shadows.get_diagnostics().settings.quality == "pcf")
	assert(drp.set_runtime_overrides({ shadows = { enabled = false } }))
	assert(shadows.get_diagnostics().enabled)
	assert(pipeline.begin_frame(1 / 60, 800, 600))
	assert(not shadows.get_diagnostics().enabled)
	assert(drp.clear_runtime_overrides("shadows"))
	assert(pipeline.begin_frame(1 / 60))
	assert(shadows.get_diagnostics().enabled)
	assert(drp.set_runtime_overrides({ shadows = { enabled = true, quality = "off" } }))
	assert(pipeline.begin_frame(1 / 60))
	assert(not shadows.get_diagnostics().enabled)
	pipeline.finalize()
	assert(not shadows.get_diagnostics().initialized)
	assert(drp.initialize({ quality = "compatibility" }))
	assert(shadows.get_diagnostics().settings.quality == "off")
	pipeline.finalize()
end

-- Verifies atomic six-face allocation, stable residency and device/profile bounds.
local function allocation()
	local pool = atlas.new(8)
	local first = assert(atlas.allocate(pool, 1, 6))
	assert(atlas.allocate(pool, 1, 6) == first)
	assert(not atlas.allocate(pool, 2, 6) and not pool.allocations[2])
	assert(#atlas.allocate(pool, 3, 1) == 1)
	atlas.retain(pool, { [3] = true })
	assert(#atlas.allocate(pool, 2, 6) == 6 and not pool.allocations[1])
	local c = config.resolve({atlas_size = 99999, tile_size = 512, directional_cascades = 99, max_updates_per_frame = -1}, {max_texture_size_2d = 1024})
	assert(c.atlas_size == 1024 and c.local_capacity == 4 and c.directional_cascades == 4 and c.max_updates_per_frame == 0)
end

-- Verifies production scheduling, buffer indexing, tile clears and cache failure behavior with mocked draw commands.
local function renderer()
	local old_local, old_directional = views.local_light, views.directional
	local function matrix(value)
		local m = {}
		for row = 0, 3 do for column = 0, 3 do m["m" .. row .. column] = row == column and 1 or 0 end end
		m.m03 = value or 0
		return m
	end
	local function items(light, count)
		local result = {}
		for i = 1, count do result[i] = {matrix = matrix(light.position[1] + i), view = matrix(), projection = matrix(), near = 0.05, far = light.range} end
		return result
	end
	views.local_light = function(light) return items(light, light.type == 1 and 6 or 1) end
	views.directional = function(light, _, c) return items(light, c.directional_cascades), {20, 100} end
	_G.vmath = { matrix4 = matrix, vector4 = function(x,y,z,w) return {x=x,y=y,z=z,w=w} end }
	_G.graphics = setmetatable({}, {__index = function(_, key) return key end})
	local targets, buffers, id, bound, material, data = {}, {}, 0, nil, nil, nil
	local ssbo_bound = false
	local clear_count, draw_count, fail_draw, fail_submit = 0, 0, false, false
	_G.render = setmetatable({
		RENDER_TARGET_DEFAULT = "screen", TEXTURE_BIT = 1,
		predicate = function(tags) return tags[1] end,
		render_target = function(name, settings) assert(not targets[name]); targets[name] = settings; return name end,
		delete_render_target = function(name) assert(targets[name] and bound ~= name); targets[name] = nil end,
		set_render_target = function(name) assert(name == "screen" or targets[name]); bound = name end,
		set_viewport = function(_, _, w, h) assert(w > 0 and h > 0) end,
		enable_material = function(name) material = name end,
		disable_material = function() material = nil end,
		clear = function() assert(bound == "drp_shadow_fallback", "full atlas clear would destroy cached tiles") end,
		draw = function(predicate)
			if fail_draw then error("simulated draw failure") end
			if predicate == "drp_shadow_clear" then assert(material == "drp_shadow_clear"); clear_count = clear_count + 1
			else draw_count = draw_count + 1 end
		end,
		enable_texture = function(_, name) assert(targets[name] and bound ~= name, "attachment feedback") end,
	}, {__index = function() return function() end end})
	local lights, scene_revision = {}, 1
	for i, kind in ipairs({0, 1, 2}) do lights[i] = {id = i, index = i - 1, type = kind, range = 50, position = {0,0,0}, direction = {0,0,-1},
		outer_cone = 1, priority = 0, bias = 0.001, normal_bias = 0.02, softness = 1.5, cache = false} end
	_G.drp_native = {
		get_capabilities = function() return {} end,
		get_shadow_lights = function() return lights, scene_revision end,
		pack_floats = function(values) data = values; return string.rep("\0", #values * 4) end,
		submit_fullscreen = function() return not fail_submit end,
		create_storage_buffer = function(size) id=id+1; buffers[id]=size; return id end,
		update_storage_buffer = function(handle, offset, bytes) assert(buffers[handle] == #bytes and offset == 0); return true end,
		bind_storage_buffer = function(handle, set, binding) assert(buffers[handle] and set == 2 and binding == 6); ssbo_bound = true; return true end,
		unbind_storage_buffer = function(handle) assert(buffers[handle]); ssbo_bound = false; return true end,
		delete_storage_buffer = function(handle) assert(buffers[handle]); buffers[handle] = nil; return true end,
	}
	local context = {frame = 0, camera = {component = "camera", near = 0.1}, viewport = {width = 800, height = 600},
		profile = {settings = {rendering = {path = "forward_plus"}, shadows = {quality = "pcf", directional_cascades = 2, max_updates_per_frame = 9}}}}
	local function frame()
		context.frame = context.frame + 1
		clear_count, draw_count = 0, 0
		shadows.render(context)
		assert(bound == "screen" and material == nil, "passes must restore scene state")
		local constants = {}
		shadows.bind_scene(constants); shadows.unbind_scene()
		assert(ssbo_bound, "queued draws still need the immediate native SSBO binding")
		return shadows.get_diagnostics(), constants.drp_shadow_settings.x
	end
	shadows.initialize(context)
	local info = frame()
	assert(info.available and info.updated_views == 9 and info.shadowed_lights == 3)
	assert(clear_count == 9 and draw_count == 27)
	assert(data[3] == 2 and data[15] == 6 and data[27] == 1)
	assert(frame().updated_views == 9, "dynamic geometry must redraw by default")
	for _, light in ipairs(lights) do light.cache = true end
	assert(frame().cached_views == 9 and clear_count == 0)
	lights[2].index = 7
	info = frame()
	assert(info.cached_views == 9 and data[15] == 0 and data[7*12+3] == 6, "repacked engine indices must not invalidate or misassociate maps")
	scene_revision = 2
	assert(frame().updated_views == 9)
	lights[2].position[1] = 5
	assert(frame().updated_views == 6)
	context.profile.settings.shadows.max_updates_per_frame = 5
	shadows.on_profile_changed(context)
	lights[2].position[1] = 6
	info = frame()
	assert(info.deferred_views == 6 and info.shadowed_lights == 2 and data[7*12+3] == 0, "dirty point faces must be atomic and unpublished")
	context.profile.settings.shadows.max_updates_per_frame = 9
	shadows.on_profile_changed(context)
	assert(frame().updated_views == 6)
	lights[2] = lights[3]; lights[3] = nil
	assert(frame().shadowed_lights == 2 and data[7*12+3] == 0)
	fail_submit = true
	local failed, enabled = frame()
	assert(not failed.available and enabled == 0)
	fail_submit = false
	assert(frame().available, "transient render failures must retry")
	scene_revision = 3; fail_draw = true
	failed, enabled = frame()
	assert(not failed.available and enabled == 0)
	fail_draw = false
	assert(frame().updated_views == 3, "failed passes must not commit cache entries")
	lights = {}
	assert(not frame().available and not targets.drp_shadow_local, "unused atlases must be released")
	context.profile.settings.shadows.enabled = false
	shadows.on_profile_changed(context)
	shadows.render(context)
	assert(not shadows.get_diagnostics().available and not targets.drp_shadow_local)
	shadows.finalize()
	assert(next(targets) == nil and next(buffers) == nil)
	views.local_light, views.directional = old_local, old_directional
end

-- Runs stateful checks with globals restored for other feature tests.
function M.run()
	local saved = {}
	local names = {"render", "graphics", "vmath", "camera", "sys", "hash", "drp_native"}
	for _, name in ipairs(names) do saved[name] = rawget(_G, name); _G[name] = nil end
	local ok, err = xpcall(function() settings_lifecycle(); allocation(); renderer() end, debug.traceback)
	for _, name in ipairs(names) do _G[name] = saved[name] end
	assert(ok, err)
	return true
end
return M
