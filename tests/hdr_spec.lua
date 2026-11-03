local M = {}

-- Verifies HDR activation and fallback without scene geometry, including native submission failures.
function M.run()
	local saved = {}
	for _, name in ipairs({ "render", "graphics", "vmath", "camera", "sys", "hash", "drp_native" }) do
		saved[name] = rawget(_G, name)
	end
	_G.hash = function(value) return value end
	_G.graphics = setmetatable({}, { __index = function(_, key) return key end })
	_G.vmath = {
		vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end,
		matrix4 = function() return {} end,
	}
	local events, targets = {}, {}
	local next_id, allocations, deletions, attempts = 0, 0, 0, 0
	local fail_allocation = false
	local fail_submission, submitted = false, false
	local submissions = 0
	local active_target, bound_texture
	local function event(name, ...)
		events[#events + 1] = { name, ... }
	end
	local function submit_fullscreen(material)
		assert(material == "/drp/features/hdr/tonemap.materialc")
		assert(next(targets), "submit only after target allocation succeeds")
		submissions = submissions + 1
		event("submit")
		if fail_submission then return nil, "render list full" end
		submitted = true
		return true
	end
	_G.drp_native = nil
	_G.render = setmetatable({
		RENDER_TARGET_DEFAULT = "backbuffer",
		predicate = function(tags) return tags[1] end,
		constant_buffer = function() return {} end,
		render_target = function(_, attachments)
			attempts = attempts + 1
			if fail_allocation then error("allocation failure") end
			next_id = next_id + 1
			targets[next_id] = attachments
			allocations = allocations + 1
			assert(attachments.BUFFER_TYPE_COLOR0_BIT.format == "TEXTURE_FORMAT_RGBA16F")
			assert(attachments.BUFFER_TYPE_DEPTH_BIT)
			return next_id
		end,
		set_render_target = function(target)
			assert(target == "backbuffer" or targets[target], "deleted target rebound")
			active_target = target
			event("target", target)
		end,
		delete_render_target = function(target)
			assert(targets[target] and active_target ~= target, "deleting bound/dead target")
			targets[target] = nil
			deletions = deletions + 1
		end,
		enable_texture = function(_, target)
			assert(targets[target] and target ~= active_target, "render-target feedback")
			bound_texture = target
			event("texture", target)
		end,
		disable_texture = function() bound_texture = nil; event("unbind") end,
		draw = function(predicate, options)
			assert(predicate == "drp_hdr_tonemap")
			assert(submitted, "resolve requires a fullscreen entry submitted this frame")
			assert(active_target == "backbuffer" and targets[bound_texture])
			event("resolve", options.constants.hdr_settings.x)
		end,
	}, { __index = function(_, name) return function(...) event(name, ...) end end })
	local hdr = require("drp.features.hdr.hdr")
	local resources = require("drp.internal.resources")
	resources.reset()
	hdr.initialize()
	local context = {
		profile = { settings = { rendering = { hdr = true, hdr_exposure = 0 }, lighting = {} } },
		capabilities = { strict = true, features = { float_render_targets = true }, limits = {} },
		viewport = { width = 960, height = 640 },
	}
	local function begin()
		events = {}
		submitted = false
		hdr.begin_frame(context)
		return hdr.get_diagnostics()
	end
	local function frame()
		local info = begin()
		render.set_render_target(hdr.get_render_target())
		hdr.scene_rendered()
		hdr.render()
		assert(not bound_texture, "resolve must unbind its scene texture")
		return info
	end
	assert(not frame().available and allocations == 0, "missing bridge must retain LDR without allocation")
	_G.drp_native = {}
	assert(not frame().available and allocations == 0, "old bridge must retain LDR without allocation")
	local native = require("drp.internal.native")
	local ok, err = native.submit_fullscreen("/drp/features/hdr/tonemap.materialc")
	assert(not ok and err, "old bridges must return a graceful unsupported result")
	_G.drp_native.submit_fullscreen = submit_fullscreen
	local info = frame()
	assert(info.available and allocations == 1 and submissions == 1, "renderer must activate HDR without a scene object")
	assert(info.color_bytes == 960 * 640 * 8)
	assert(hdr.output_settings().x == 1)
	frame()
	assert(allocations == 1 and submissions == 2, "stable frames must reuse the target and resubmit geometry")
	-- A transient submission failure falls back before scene drawing and recovers without target churn.
	fail_submission = true
	info = frame()
	assert(not info.available and info.reason:match("render list full"))
	assert(hdr.get_render_target() == "backbuffer" and hdr.output_settings().x == 0)
	assert(allocations == 1 and deletions == 0, "retain the target for submission retry")
	for _, call in ipairs(events) do assert(call[1] ~= "resolve", "failed submission must not resolve") end
	fail_submission = false
	info = frame()
	assert(info.available and not info.reason and allocations == 1 and submissions == 4)
	context.profile.settings.rendering.hdr_exposure = 2
	frame()
	local resolve
	for _, call in ipairs(events) do if call[1] == "resolve" then resolve = call end end
	assert(resolve and resolve[2] == 2 and allocations == 1)
	-- No active camera / scene submission: do not display stale target contents.
	begin(); hdr.render()
	assert(#events == 1 and events[1][1] == "submit")
	-- An enabled debug view must remain display-referred and skip the resolve.
	context.profile.settings.lighting.cluster_debug = true
	assert(not frame().available and next(targets) == nil and hdr.output_settings().x == 0)
	context.profile.settings.lighting.cluster_debug = false
	assert(frame().available)
	-- Resize and HDR/profile toggles have balanced resource ownership.
	for index = 1, 40 do
		context.viewport.width = 640 + index
		context.viewport.height = 480 + index
		context.profile.settings.rendering.hdr = index % 3 ~= 0
		local previous_submissions = submissions
		info = frame()
		assert(info.available == context.profile.settings.rendering.hdr)
		assert(submissions - previous_submissions == (info.available and 1 or 0), "disabled HDR must not submit geometry")
		assert(allocations - deletions == (info.available and 1 or 0))
	end
	context.profile.settings.rendering.hdr = true
	context.capabilities.features.float_render_targets = false
	assert(not frame().available and next(targets) == nil)
	context.capabilities.features.float_render_targets = nil
	assert(not frame().available, "strict mode rejects unknown support")
	context.capabilities.strict = false
	assert(frame().available, "non-strict mode can attempt an unknown target")
	context.capabilities.limits.max_texture_size_2d = 128
	assert(not frame().available and next(targets) == nil)
	context.capabilities.limits.max_texture_size_2d = nil
	fail_allocation = true
	assert(not frame().available and hdr.output_settings().x == 0)
	local failed_attempts = attempts
	frame()
	assert(attempts == failed_attempts, "allocation failure must not retry every frame")
	fail_allocation = false
	context.transition = {}
	assert(frame().available, "profile reload can retry allocation")
	context.transition = nil
	for _, value in ipairs({ math.huge, -math.huge, 0 / 0, "bad" }) do
		context.profile.settings.rendering.hdr_exposure = value
		assert(frame().exposure == 0)
	end
	context.profile.settings.rendering.hdr_exposure = 100
	assert(frame().exposure == 16)
	_G.drp_native = nil
	assert(not frame().available and next(targets) == nil, "bridge loss must release the HDR target")
	hdr.finalize()
	assert(allocations == deletions)
	resources.reset()
	for _, name in ipairs({ "render", "graphics", "vmath", "camera", "sys", "hash", "drp_native" }) do
		_G[name] = saved[name]
	end
	return true
end

return M
