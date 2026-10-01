local utils = require("drp.internal.utils")

local M = { name = "shadows" }

local state = {
	initialized = false,
	enabled = false,
	settings = {},
	reason = "not initialized",
}

local function configure(context)
	local profile = context.profile or {}
	local settings = profile.settings or {}
	-- Preserve the resolved request for diagnostics without mutating the shared
	-- feature context. Validation and effective budgets belong to the actual
	-- shadow implementation; these values are not yet rendering settings.
	state.settings = type(settings.shadows) == "table" and utils.copy(settings.shadows) or {}
	local quality = state.settings.quality
	local has_quality = type(quality) == "string" and quality ~= "" and quality ~= "off"
	state.enabled = state.settings.enabled ~= false and quality ~= "off"
		and (state.settings.enabled == true or has_quality)
	state.reason = state.enabled and "shadow rendering is not implemented" or "disabled by settings"
end

function M.initialize(context)
	state.initialized = true
	configure(context)
end

function M.on_profile_changed(context)
	configure(context)
end

function M.render()
	-- Reserved before clustered scene rendering. Once light registration and
	-- index lookup are available, render dirty shadow views here and publish
	-- their metadata for the scene passes. The scaffold issues no GPU commands.
end

function M.get_diagnostics()
	return {
		initialized = state.initialized,
		enabled = state.enabled,
		available = false,
		effective_quality = "off",
		reason = state.reason,
		settings = utils.copy(state.settings),
	}
end

function M.finalize()
	state.initialized = false
	state.enabled = false
	state.settings = {}
	state.reason = "not initialized"
end

return M
