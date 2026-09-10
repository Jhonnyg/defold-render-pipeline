local capabilities = require("drp.capabilities")
local pipeline = require("drp.pipeline")
local quality = require("drp.quality")

local M = {}

local function assert_equal(expected, actual, message)
	assert(expected == actual, string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
end

function M.run()
	local unknown_caps = capabilities.detect({ platform = "macos" })
	local balanced = assert(quality.resolve("balanced", unknown_caps))
	assert_equal("balanced", balanced.effective, "unknown capabilities are allowed in non-strict mode")

	local unsupported_caps = capabilities.detect({
		platform = "macos",
		features = {
			compute_shaders = false,
			storage_buffers = false,
			float_render_targets = true,
		},
	})
	local fallback = assert(quality.resolve("high", unsupported_caps))
	assert_equal("compatibility", fallback.effective, "unsupported Forward+ profiles fall back")
	assert(#fallback.reasons >= 2, "fallback should retain rejection reasons")

	local supported_web = capabilities.detect({
		platform = "html5",
		features = {
			compute_shaders = true,
			storage_buffers = true,
			float_render_targets = true,
		},
	})
	local web = assert(quality.resolve("balanced", supported_web))
	assert_equal(48, web.profile.settings.lighting.max_lights_per_cluster, "platform override is applied")

	assert(quality.register("test_custom", {
		name = "test_custom",
		extends = "balanced",
		fallback = "compatibility",
		settings = {
			rendering = { render_scale = 0.8 },
		},
	}))
	local custom = assert(quality.resolve("test_custom", supported_web))
	assert_equal("forward_plus", custom.profile.settings.rendering.path, "parent settings are inherited")
	assert_equal(0.8, custom.profile.settings.rendering.render_scale, "child settings override parent")
	quality.unregister("test_custom")

	pipeline.finalize()
	assert(pipeline.initialize({
		quality = "compatibility",
		platform = "macos",
	}))
	local request = assert(pipeline.set_quality("balanced"))
	assert_equal("balanced", request.requested, "request is queued")
	assert_equal("balanced", pipeline.get_requested_quality(), "pending request is observable")
	assert_equal("compatibility", pipeline.get_effective_quality(), "active profile is unchanged before frame boundary")
	local transition = assert(pipeline.begin_frame(1 / 60))
	assert_equal("balanced", transition.current.effective, "request activates at frame boundary")
	pipeline.finalize()

	return true
end

return M
