local capabilities = require("drp.capabilities")
local quality = require("drp.quality")
local resources = require("drp.resources")
local utils = require("drp.utils")

local M = {}

local state = {
	initialized = false,
	frame = 0,
	capabilities = nil,
	active = nil,
	pending = nil,
	runtime_overrides = {},
	listeners = {},
	next_listener_handle = 1,
}

local function config_string(key, default_value)
	if _G.sys and sys.get_config then
		local ok, value = pcall(sys.get_config, key, default_value)
		if ok and value ~= nil and value ~= "" then
			return value
		end
	end
	return default_value
end

local function config_boolean(key, default_value)
	local fallback = default_value and "1" or "0"
	local value = tostring(config_string(key, fallback)):lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
end

local function snapshot_resolution(resolution)
	return resolution and utils.copy(resolution) or nil
end

local function snapshot_state()
	return {
		initialized = state.initialized,
		frame = state.frame,
		requested_quality = state.pending and state.pending.requested or (state.active and state.active.requested or nil),
		effective_quality = state.active and state.active.effective or nil,
		pending_quality = state.pending and state.pending.requested or nil,
		active_profile = state.active and utils.copy(state.active.profile) or nil,
		capabilities = utils.copy(state.capabilities),
	}
end

local function resolve(name)
	local resolution, err = quality.resolve(name, state.capabilities)
	if not resolution then
		return nil, err
	end
	return quality.with_settings_overrides(resolution, state.runtime_overrides)
end

local function notify(transition)
	for handle, callback in pairs(state.listeners) do
		local ok, err = pcall(callback, utils.copy(transition))
		if not ok then
			print(string.format("DRP quality listener %d failed: %s", handle, tostring(err)))
		end
	end
end

local function queue_requested_profile(name)
	local resolution, err = resolve(name)
	if not resolution then
		return nil, err
	end
	state.pending = resolution
	return snapshot_resolution(resolution)
end

function M.initialize(options)
	if state.initialized then
		return snapshot_state()
	end

	options = options or {}
	local capability_overrides = utils.copy(options.capabilities or {})
	if options.platform then
		capability_overrides.platform = options.platform
	end
	if options.strict_capabilities ~= nil then
		capability_overrides.strict = options.strict_capabilities == true
	else
		capability_overrides.strict = config_boolean("drp.strict_capabilities", false)
	end

	state.capabilities = capabilities.detect(capability_overrides)
	state.runtime_overrides = utils.copy(options.overrides or {})
	state.frame = 0

	local requested = options.quality or config_string("drp.default_profile", "balanced")
	local resolution, err = resolve(requested)
	if not resolution then
		local fallback = config_string("drp.fallback_profile", "compatibility")
		resolution, err = resolve(fallback)
		if not resolution then
			return nil, err
		end
		resolution.requested = requested
		resolution.reasons[#resolution.reasons + 1] = "configured profile could not be loaded; used '" .. fallback .. "'"
	end

	state.active = resolution
	state.pending = nil
	state.initialized = true
	return snapshot_state()
end

function M.finalize()
	resources.reset()
	state.initialized = false
	state.frame = 0
	state.capabilities = nil
	state.active = nil
	state.pending = nil
	state.runtime_overrides = {}
	state.listeners = {}
	state.next_listener_handle = 1
	return true
end

function M.reload()
	if not state.initialized then
		return M.initialize()
	end
	return queue_requested_profile(state.active.requested)
end

function M.begin_frame(dt)
	if not state.initialized then
		local initialized, err = M.initialize()
		if not initialized then
			return nil, err
		end
	end

	state.frame = state.frame + 1
	if not state.pending then
		return nil
	end

	local previous = state.active
	state.active = state.pending
	state.pending = nil

	local transition = {
		frame = state.frame,
		dt = dt or 0,
		previous = snapshot_resolution(previous),
		current = snapshot_resolution(state.active),
	}
	notify(transition)
	return transition
end

function M.is_initialized()
	return state.initialized
end

function M.get_state()
	return snapshot_state()
end

function M.get_capabilities()
	return utils.copy(state.capabilities)
end

function M.set_capabilities(capability_overrides)
	if not state.initialized then
		return nil, "DRP must be initialized before capabilities can be changed"
	end
	state.capabilities = capabilities.detect(capability_overrides or {})
	return queue_requested_profile(state.active.requested)
end

function M.get_requested_quality()
	return state.pending and state.pending.requested or (state.active and state.active.requested or nil)
end

function M.get_effective_quality()
	return state.active and state.active.effective or nil
end

function M.get_active_profile()
	return state.active and utils.copy(state.active.profile) or nil
end

function M.set_quality(name)
	if not state.initialized then
		local initialized, err = M.initialize()
		if not initialized then
			return nil, err
		end
	end
	if type(name) ~= "string" or name == "" then
		return nil, "quality profile name must be a non-empty string"
	end
	return queue_requested_profile(name)
end

function M.set_runtime_overrides(overrides)
	if type(overrides) ~= "table" then
		return nil, "runtime overrides must be a table"
	end
	if not state.initialized then
		return nil, "DRP must be initialized before runtime overrides can be changed"
	end
	state.runtime_overrides = utils.copy(overrides)
	return queue_requested_profile(state.active.requested)
end

function M.clear_runtime_overrides()
	return M.set_runtime_overrides({})
end

function M.on_quality_changed(callback)
	if type(callback) ~= "function" then
		return nil, "quality listener must be a function"
	end
	local handle = state.next_listener_handle
	state.next_listener_handle = handle + 1
	state.listeners[handle] = callback
	return handle
end

function M.remove_quality_listener(handle)
	if not state.listeners[handle] then
		return false
	end
	state.listeners[handle] = nil
	return true
end

return M
