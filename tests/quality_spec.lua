local capabilities = require("drp.internal.capabilities")
local pipeline = require("drp.internal.pipeline")
local quality = require("drp.internal.quality")
local utils = require("drp.internal.utils")

local M = {}

local function assert_equal(expected, actual, message)
	assert(expected == actual, string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
end

function M.run()
	local source = {
		nested = { value = 1 },
		items = { "a", "b" },
	}
	local copied = utils.copy(source)
	copied.nested.value = 2
	assert_equal(1, source.nested.value, "deep copies do not mutate their source")

	local merged = utils.merge({
		nested = { inherited = true, overridden = false },
		items = { "old" },
	}, {
		nested = { overridden = true },
		items = { "new", "values" },
	})
	assert_equal(true, merged.nested.inherited, "map values are merged recursively")
	assert_equal(true, merged.nested.overridden, "nested values override their destination")
	assert_equal(2, #merged.items, "arrays replace rather than merge")
	assert_equal("new", merged.items[1], "replacement arrays are copied")
	assert_equal("a, b", utils.join(source.items, ", "), "array values can be joined")

	local previous_native = rawget(_G, "drp_native")
	_G.drp_native = {
		get_capabilities = function()
			return {
				source = "test-native",
				adapter = "test-adapter",
				features = {
					compute_shaders = true,
					storage_buffers = true,
				},
				limits = {
					max_storage_buffer_range = 4096,
				},
			}
		end,
	}
	local native_caps = capabilities.detect({
		features = { storage_buffers = false },
	})
	assert_equal("test-native", native_caps.source, "native provider is merged over the Lua baseline")
	assert_equal("test-adapter", native_caps.adapter, "native adapter is reported")
	assert_equal(true, native_caps.features.compute_shaders, "native features are reported")
	assert_equal(false, native_caps.features.storage_buffers, "explicit overrides win over native features")
	assert_equal(4096, native_caps.limits.max_storage_buffer_range, "native limits are reported")
	_G.drp_native = previous_native

	local unknown_caps = capabilities.detect({ platform = "macos" })
	local balanced = assert(quality.resolve("balanced", unknown_caps))
	assert_equal("balanced", balanced.effective, "unknown capabilities are allowed in non-strict mode")
	assert_equal(false, balanced.profile.settings.lighting.cluster_debug,
		"clustered PBR shading is enabled by default")

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
	assert_equal("forward", fallback.profile.settings.rendering.path,
		"compatibility keeps the conventional forward path")
	assert(#fallback.reasons >= 2, "fallback should retain rejection reasons")
	local invalid_path = quality.resolve("compatibility", unsupported_caps, {
		rendering = { path = "forward_plus" },
	})
	assert_equal(nil, invalid_path, "runtime path overrides cannot bypass core GPU requirements")

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

	local debug_enabled = quality.with_settings_overrides(web, {
		lighting = { cluster_debug = true },
	})
	assert_equal(true, debug_enabled.profile.settings.lighting.cluster_debug,
		"runtime settings can enable the clustered heatmap")
	assert_equal(false, web.profile.settings.lighting.cluster_debug,
		"settings overrides do not mutate the resolved profile")

	pipeline.finalize()
	assert(pipeline.initialize({
		quality = "compatibility",
		platform = "macos",
	}))
	local request = assert(pipeline.set_quality("balanced"))
	assert_equal("balanced", request.requested, "request is queued")
	assert_equal("balanced", pipeline.get_requested_quality(), "pending request is observable")
	assert_equal("compatibility", pipeline.get_effective_quality(), "active profile is unchanged before frame boundary")
	local transition = assert(pipeline.begin_frame(1 / 60, 800, 600))
	assert_equal("balanced", transition.current.effective, "request activates at frame boundary")
	assert(pipeline.render())
	local pipeline_state = pipeline.get_state()
	assert_equal(800, pipeline_state.viewport.width, "frame width is retained")
	assert_equal(600, pipeline_state.viewport.height, "frame height is retained")

	local no_transition, frame_error = pipeline.begin_frame(1 / 60, 800, 600)
	assert_equal(nil, no_transition, "a stable frame has no quality transition")
	assert_equal(nil, frame_error, "a stable frame succeeds")

	pipeline.finalize()

	return true
end

return M
