local drp = require("drp.drp")

local M = {}

local function settings(result)
	return assert(result).profile.settings
end

local function start(overrides)
	drp.finalize()
	assert(drp.initialize({
		quality = "test_overrides",
		capabilities = { features = { compute_shaders = false, storage_buffers = false } },
		overrides = overrides,
	}))
end

-- Verifies incremental updates compose, preserve false, replace arrays, and copy caller data.
local function test_merge()
	start({ shadows = { quality = "pcf" }, post = { dof = true } })
	assert(drp.set_runtime_overrides({ rendering = { hdr = true, hdr_exposure = 1 } }))
	local patch = { rendering = { hdr_exposure = 2 }, shadows = { color = { 0.2, 0.3, 0.4 } } }
	local result = assert(drp.set_runtime_overrides(patch))
	assert(result.profile.settings.rendering.hdr == true)
	assert(result.profile.settings.shadows.quality == "pcf")
	assert(result.profile.settings.post.dof == true)
	patch.shadows.color[1] = 99
	patch.rendering.hdr_exposure = 99
	result.profile.settings.shadows.color[2] = 99
	local s = settings(drp.set_runtime_overrides({}))
	assert(s.rendering.hdr_exposure == 2 and s.shadows.color[1] == 0.2 and s.shadows.color[2] == 0.3)
	s = settings(drp.set_runtime_overrides({ rendering = { hdr = false }, shadows = { color = { 0.5 } } }))
	assert(s.rendering.hdr == false and s.rendering.hdr_exposure == 2)
	assert(#s.shadows.color == 1 and s.shadows.color[1] == 0.5)
	s = settings(drp.set_runtime_overrides({ rendering = { render_scale = 0.5 } }))
	assert(s.rendering.hdr == false and s.shadows.quality == "pcf")
	assert(drp.get_active_profile().settings.rendering.render_scale == 1, "updates must wait for the frame boundary")
	assert(drp.begin_frame(1 / 60))
	assert(drp.get_active_profile().settings.rendering.render_scale == 0.5)
	assert(drp.get_profile("test_overrides").settings.shadows.color[1] == 0, "registered defaults must stay unchanged")
end

-- Verifies path clearing restores defaults without deleting siblings, including false and empty ancestors.
local function test_clear_paths()
	start({
		rendering = { hdr = true, hdr_exposure = 2 },
		shadows = { quality = "pcf", color = { 0.3, 0.2, 0.1 } },
		post = { gtao = false },
		custom = { mode = { nested = { flag = false } } },
	})
	local s = settings(drp.clear_runtime_overrides("rendering.hdr_exposure"))
	assert(s.rendering.hdr_exposure == 0 and s.rendering.hdr == true)
	assert(s.shadows.quality == "pcf" and s.shadows.color[1] == 0.3)
	s = settings(drp.clear_runtime_overrides("shadows.color"))
	assert(#s.shadows.color == 3 and s.shadows.color[1] == 0 and s.shadows.quality == "pcf")
	s = settings(drp.clear_runtime_overrides("post.gtao"))
	assert(s.post.gtao == true, "false overrides must be removable")
	s = settings(drp.clear_runtime_overrides("custom.mode.nested.flag"))
	assert(s.custom.mode == "default", "empty ancestors must stop masking the profile's scalar default")
	s = settings(drp.clear_runtime_overrides("shadows"))
	assert(s.shadows.quality == "off" and s.rendering.hdr == true)
	for _, path in ipairs({ "unknown", "unknown.child", "rendering.missing", "rendering.hdr.child" }) do
		s = settings(drp.clear_runtime_overrides(path))
		assert(s.rendering.hdr == true and s.rendering.hdr_exposure == 0)
	end
	for _, path in ipairs({ "", ".rendering", "rendering.", "rendering..hdr", "rendering. hdr", 42, false, {} }) do
		local result, err = drp.clear_runtime_overrides(path)
		assert(result == nil and type(err) == "string", "invalid paths should return an error")
	end
	assert(settings(drp.set_runtime_overrides({})).rendering.hdr == true)
	s = settings(drp.clear_runtime_overrides(nil))
	assert(s.rendering.hdr == false and s.rendering.hdr_exposure == 0)
	assert(drp.set_runtime_overrides({ rendering = { hdr_exposure = 3 } }))
	s = settings(drp.clear_runtime_overrides())
	assert(s.rendering.hdr_exposure == 0, "omitted path also clears everything")
	assert(drp.begin_frame(1 / 60))
	assert(drp.get_active_profile().settings.rendering.hdr == false)
end

-- Verifies override changes retain a pending quality request and failed merges commit nothing.
local function test_pending_and_failed_updates()
	start({ shadows = { quality = "pcf" } })
	assert(drp.set_quality("test_overrides_next"))
	local result = assert(drp.set_runtime_overrides({ rendering = { hdr_exposure = 2 } }))
	assert(result.requested == "test_overrides_next" and result.profile.settings.rendering.render_scale == 0.75)
	local rejected, err = drp.set_runtime_overrides({ rendering = { path = "forward_plus", hdr = true } })
	assert(not rejected and err, "an unsupported render path must fail validation")
	assert(drp.get_requested_quality() == "test_overrides_next")
	result = assert(drp.clear_runtime_overrides("rendering.hdr_exposure"))
	assert(result.requested == "test_overrides_next")
	assert(result.profile.settings.rendering.hdr == false and result.profile.settings.shadows.quality == "pcf")
	assert(drp.begin_frame(1 / 60))
	assert(drp.get_effective_quality() == "test_overrides_next")
	assert(drp.set_quality("test_overrides"))
	assert(drp.clear_runtime_overrides(nil).requested == "test_overrides")
	assert(drp.begin_frame(1 / 60))
	assert(drp.get_effective_quality() == "test_overrides")
end

-- Verifies failed clearing preserves the old overrides and already queued resolution.
local function test_failed_clear()
	start({ rendering = { hdr_exposure = 2 }, shadows = { quality = "pcf" } })
	assert(drp.set_quality("test_overrides_next"))
	assert(drp.unregister_profile("test_overrides_next"))
	for _, path in ipairs({ "rendering.hdr_exposure", "shadows" }) do
		local result, err = drp.clear_runtime_overrides(path)
		assert(not result and err)
	end
	local result, err = drp.clear_runtime_overrides(nil)
	assert(not result and err)
	assert(drp.get_requested_quality() == "test_overrides_next")
	assert(drp.begin_frame(1 / 60), "the queued resolution must survive failed clearing")
	local active = drp.get_active_profile().settings
	assert(active.rendering.hdr_exposure == 2 and active.shadows.quality == "pcf")
	local s = settings(drp.set_quality("test_overrides"))
	assert(s.rendering.hdr_exposure == 2 and s.shadows.quality == "pcf", "failed clearing must preserve stored overrides")
end

-- Exercises the public override API across initialization, frame boundaries, and validation failures.
function M.run()
	assert(drp.register_profile("test_overrides", {
		extends = "compatibility",
		settings = { shadows = { color = { 0, 0, 0 } }, post = { gtao = true }, custom = { mode = "default" } },
	}))
	assert(drp.register_profile("test_overrides_next", {
		extends = "test_overrides", settings = { rendering = { render_scale = 0.75 } },
	}))
	test_merge()
	test_clear_paths()
	test_pending_and_failed_updates()
	test_failed_clear()
	drp.finalize()
	assert(drp.unregister_profile("test_overrides"))
	local result, err = drp.clear_runtime_overrides(nil)
	assert(not result and err)
	result, err = drp.clear_runtime_overrides("rendering.hdr_exposure")
	assert(not result and err)
	return true
end

return M
