local config = require("drp.internal.config")
local frame_camera = require("drp.internal.camera")
local capabilities = require("drp.internal.capabilities")
local features = require("drp.internal.features")
local presets = require("drp.features.presets")
local debug_views = require("drp.internal.debug")
local debug_overlay = require("drp.internal.debug_overlay")
local debug_controls = require("drp.internal.debug_controls")
local native = require("drp.internal.native")
local quality = require("drp.internal.quality")
local resources = require("drp.internal.resources")
local scene = require("drp.internal.scene")
local utils = require("drp.internal.utils")

local M = {}

local state = {
	initialized = false,
	frame = 0,
	frame_dt = 0,
	frame_transition = nil,
	capabilities = nil,
	active = nil,
	pending = nil,
	runtime_overrides = {},
	listeners = {},
	next_listener_handle = 1,
	viewport = nil,
	feature_context = nil,
	debug_requesters = {},
}

-- Defined alongside runtime override handling below.
local update_debug_control

local function snapshot_resolution(resolution)
	return resolution and utils.copy(resolution) or nil
end

local function snapshot_state()
	return {
		initialized = state.initialized,
		features = features.get_features(),
		frame = state.frame,
		requested_quality = state.pending and state.pending.requested or (state.active and state.active.requested or nil),
		effective_quality = state.active and state.active.effective or nil,
		pending_quality = state.pending and state.pending.requested or nil,
		active_profile = state.active and utils.copy(state.active.profile) or nil,
		capabilities = utils.copy(state.capabilities),
		viewport = utils.copy(state.viewport),
	}
end

local function feature_context(dt, transition)
	return {
		frame = state.frame,
		dt = dt ~= nil and dt or state.frame_dt,
		quality = state.active,
		profile = state.active and state.active.profile or nil,
		capabilities = state.capabilities,
		viewport = state.viewport,
		transition = transition or state.frame_transition,
	}
end

local function resolve(name)
	local resolution, err = quality.resolve(name, state.capabilities, state.runtime_overrides, features.apply_defaults({}))
	if not resolution then
		return nil, err
	end
	return resolution
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
	options = options or {}
	if state.initialized then
		if options.features ~= nil then
			return nil, "select features only in render-script initialization, before DRP starts"
		end
		return snapshot_state()
	end

	local modules = options.features
	if modules == nil then
		modules = config.boolean("drp.clustered_resources", true) and presets.default() or presets.compatibility()
	end
	local configured, configuration_error = features.configure(modules)
	if not configured then
		return nil, configuration_error
	end
	local capability_overrides = utils.copy(options.capabilities or {})
	if options.platform then
		capability_overrides.platform = options.platform
	end
	if options.strict_capabilities ~= nil then
		capability_overrides.strict = options.strict_capabilities == true
	else
		capability_overrides.strict = config.boolean("drp.strict_capabilities", false)
	end

	state.capabilities = capabilities.detect(capability_overrides)
	state.runtime_overrides = utils.copy(options.overrides or {})
	state.frame = 0
	state.frame_dt = 0
	state.frame_transition = nil

	local requested = options.quality or config.string("drp.default_profile", "balanced")
	local resolution, err = resolve(requested)
	if not resolution then
		local fallback = config.string("drp.fallback_profile", "compatibility")
		resolution, err = resolve(fallback)
		if not resolution then
			features.configure({})
			return nil, err
		end
		resolution.requested = requested
		resolution.reasons[#resolution.reasons + 1] = "configured profile could not be loaded; used '" .. fallback .. "'"
	end

	state.active = resolution
	state.pending = nil
	state.initialized = true
	state.viewport = nil
	state.feature_context = feature_context(0)

	scene.initialize()
	features.initialize(state.feature_context)
	debug_views.initialize()
	debug_overlay.initialize()
	return snapshot_state()
end

function M.finalize()
	if state.initialized then
		debug_views.finalize()
		debug_overlay.finalize()
		features.finalize(state.feature_context or feature_context(0))
		scene.finalize()
	end
	if not state.initialized then
		features.configure({})
	end
	resources.reset()
	native.reset()
	state.initialized = false
	state.frame = 0
	state.frame_dt = 0
	state.frame_transition = nil
	state.capabilities = nil
	state.active = nil
	state.pending = nil
	state.runtime_overrides = {}
	state.listeners = {}
	state.next_listener_handle = 1
	state.viewport = nil
	state.feature_context = nil
	state.debug_requesters = {}
	return true
end

function M.reload()
	if not state.initialized then
		return M.initialize()
	end
	return queue_requested_profile(state.active.requested)
end

function M.begin_frame(dt, width, height)
	if not state.initialized then
		local initialized, err = M.initialize()
		if not initialized then
			return nil, err
		end
	end
	if width ~= nil or height ~= nil then
		if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then
			return nil, "frame viewport width and height must be positive numbers"
		end
	end

	state.frame = state.frame + 1
	state.frame_dt = dt or 0
	state.frame_transition = nil
	local transition = nil
	if state.pending then
		local previous = state.active
		state.active = state.pending
		state.pending = nil
		transition = {
			frame = state.frame,
			dt = dt or 0,
			previous = snapshot_resolution(previous),
			current = snapshot_resolution(state.active),
		}
		state.frame_transition = transition
	end

	local viewport_changed = false
	if width ~= nil or height ~= nil then
		if not state.viewport or width ~= state.viewport.width or height ~= state.viewport.height then
			state.viewport = {
				width = width,
				height = height,
			}
			viewport_changed = true
		end
	end

	state.feature_context = feature_context(dt, transition)
	if transition then
		features.on_profile_changed(state.feature_context, transition)
		notify(transition)
	end
	if viewport_changed then
		features.resize(state.feature_context, width, height)
	end
	-- Quality listeners may enable or move cameras. Snapshot after those
	-- callbacks so every render stage sees the same final camera for this frame.
	state.feature_context.camera = frame_camera.snapshot()
	debug_views.begin_frame(state.feature_context)
	features.begin_frame(state.feature_context)
	return transition
end

local function control_snapshot(context)
	local settings = context.profile and context.profile.settings or {}
	local records = debug_controls.snapshot(settings, state.runtime_overrides)
	local diagnostics = {}
	for _, record in ipairs(records) do
		local feature = record.feature
		if not diagnostics[feature] then
			diagnostics[feature] = features.get_diagnostics(feature) or {}
		end
		local info = diagnostics[feature]
		local supported, reason = features.is_supported(feature, state.capabilities)
		record.editable = supported
		record.feature_available = supported and info.available ~= false
		record.feature_reason = reason or info.reason
		if record.diagnostic_key then
			record.effective_value = info[record.diagnostic_key]
		end
	end
	return records
end

local function reply_debug_status(context)
	if not next(state.debug_requesters) then
		return
	end

	-- Send plain values across script contexts. Never expose render targets or
	-- assume that the GUI and renderer share a Lua module instance.
	local status = debug_views.get_state(context)
	status.quality = state.active and state.active.effective or nil
	local controls, views
	for _, request in pairs(state.debug_requesters) do
		local sender = request.sender
		msg.post(sender, "drp_debug_status", status)
		if request.views then
			views = views or debug_views.get_views()
			msg.post(sender, "drp_debug_views_begin", { count = #views, frame = context.frame })
			for _, view in ipairs(views) do
				msg.post(sender, "drp_debug_view", view)
			end
			msg.post(sender, "drp_debug_views_end", { frame = context.frame })
		end
		if request.controls then
			controls = controls or control_snapshot(context)
			-- Stream one descriptor/value per message to stay within Defold's
			-- message-size limit as features add more controls.
			msg.post(sender, "drp_debug_controls_begin", { count = #controls, frame = context.frame })
			for _, record in ipairs(controls) do
				msg.post(sender, "drp_debug_control", record)
			end
			msg.post(sender, "drp_debug_controls_end", { frame = context.frame })
		end
		for _, err in pairs(request.errors or {}) do
			msg.post(sender, "drp_debug_control_error", err)
		end
	end
	state.debug_requesters = {}
end

function M.render()
	if not state.initialized then
		return nil, "DRP must be initialized before rendering"
	end
	local context = state.feature_context or feature_context()
	-- begin_frame has already submitted every fullscreen entry. Pre-scene
	-- features can now draw their own targets before the scene target is selected.
	features.render_before_scene(context)
	local pass = scene.create_pass(context)
	if pass then
		features.configure_scene(context, pass)
		scene.begin(context, pass)
		features.prepare_scene(context, pass)
		scene.render(context, pass)
		features.render_after_scene(context, pass)
	else
		scene.clear_background(context)
	end
	debug_views.render(context)
	debug_overlay.render(context)
	reply_debug_status(context)
	return true
end

local function bounded_debug_text(value, limit)
	local text = tostring(value)
	if #text > limit then
		return text:sub(1, limit - 3) .. "..."
	end
	return text
end

local function debug_command(message, sender)
	local command = message.command
	local controls = false
	local views = false
	local control_error
	local control_error_key
	local control_changed = false
	if command == "reset" then
		debug_views.set_view(nil)
	elseif command == "set" then
		local ok, err = debug_views.set_view(message.view)
		if not ok then
			print("DRP debug: " .. err)
		end
	elseif command == "next" or command == "previous" then
		local views = debug_views.get_views()
		local selected = debug_views.get_state().view
		local step = command == "next" and 1 or -1
		for index, view in ipairs(views) do
			if view.id == selected then
				debug_views.set_view(views[(index - 1 + step) % #views + 1].id)
				break
			end
		end
	elseif command == "views" then
		views = true
	elseif command == "controls" then
		controls = true
	elseif command == "set_control" or command == "reset_control" or command == "reset_feature" then
		controls = true
		control_changed = true
		control_error_key = command == "reset_feature"
			and ("feature:" .. tostring(message.feature)) or tostring(message.id)
		local ok, err = update_debug_control(command, message)
		if not ok then
			-- Invalid callers can supply IDs that nearly fill the incoming
			-- message. Avoid duplicating them into an oversized error reply.
			control_error = {
				id = type(message.id) == "string" and bounded_debug_text(message.id, 128) or "",
				feature = type(message.feature) == "string" and bounded_debug_text(message.feature, 64) or "",
				reason = bounded_debug_text(err, 768),
			}
		end
	elseif command ~= "status" then
		return
	end

	-- Coalesce polls/keypresses and answer after rendering, when feature
	-- availability describes the newly selected view and the current frame.
	if sender then
		local key = tostring(sender)
		local request = state.debug_requesters[key] or { sender = sender }
		request.controls = request.controls or controls
		request.views = request.views or views
		if control_changed then
			request.errors = request.errors or {}
			request.errors[control_error_key] = control_error
		end
		state.debug_requesters[key] = request
	end
end

function M.on_message(message_id, message, sender)
	if message_id == hash("drp_debug_command") then
		debug_command(message, sender)
		return
	end
	features.on_message(state.feature_context or feature_context(), message_id, message, sender)
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
	local previous = state.capabilities
	state.capabilities = capabilities.detect(capability_overrides or {})
	local resolution, err = queue_requested_profile(state.active.requested)
	if not resolution then
		state.capabilities = previous
	end
	return resolution, err
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

function M.get_feature_diagnostics(name)
	if type(name) ~= "string" or name == "" then
		return nil, "feature name must be a non-empty string"
	end
	local diagnostics = features.get_diagnostics(name)
	if not diagnostics then
		return nil, "unknown feature '" .. name .. "'"
	end
	return utils.copy(diagnostics)
end

-- Property APIs run in the renderer's Lua context, just like feature hooks.
-- Game/GUI scripts use the debug message transport when contexts are separate.
function M.get_feature_properties()
	local settings = state.active and state.active.profile.settings or {}
	return features.property_snapshot(settings, state.runtime_overrides)
end

function M.set_feature_property(id, value)
	if not state.initialized then
		return nil, "DRP must be initialized before properties can be changed"
	end
	local overrides, err = features.make_property_override(id, value)
	if not overrides then
		return nil, err
	end
	return M.set_runtime_overrides(overrides)
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

local function queue_runtime_overrides(overrides)
	-- Resolve before committing either the overrides or the pending profile.
	-- Preserve a quality request made earlier in the same frame.
	local resolution, err = quality.resolve(M.get_requested_quality(), state.capabilities, overrides, features.apply_defaults({}))
	if not resolution then
		return nil, err
	end
	state.runtime_overrides = overrides
	state.pending = resolution
	return snapshot_resolution(resolution)
end

update_debug_control = function(command, message)
	if not state.initialized then
		return nil, "DRP must be initialized before controls can be changed"
	end

	if command == "set_control" then
		local owner = type(message.id) == "string" and message.id:match("^([^.]+)%.")
		local supported, reason = features.is_supported(owner, state.capabilities)
		if not supported then
			return nil, reason
		end
		local overrides, err = debug_controls.make_override(message.id, message.value)
		if not overrides then
			return nil, err
		end
		return M.set_runtime_overrides(overrides)
	end

	local paths, err
	if command == "reset_feature" then
		paths, err = debug_controls.get_paths(message.feature)
	else
		for _, descriptor in ipairs(debug_controls.get_descriptors()) do
			if descriptor.id == message.id then
				paths = { descriptor.path }
				break
			end
		end
		err = "unknown debug control '" .. tostring(message.id) .. "'"
	end
	if not paths then
		return nil, err
	end

	-- Remove only this feature's exposed paths, then resolve once. Clearing a
	-- whole settings group would also remove other features' overrides.
	local overrides, reset_error = debug_controls.clear_overrides(state.runtime_overrides, paths)
	if not overrides then
		return nil, reset_error
	end
	return queue_runtime_overrides(overrides)
end

function M.set_runtime_overrides(overrides)
	if type(overrides) ~= "table" then
		return nil, "runtime overrides must be a table"
	end
	if not state.initialized then
		return nil, "DRP must be initialized before runtime overrides can be changed"
	end
	return queue_runtime_overrides(utils.merge(utils.copy(state.runtime_overrides), overrides))
end

function M.clear_runtime_overrides(path)
	if path ~= nil and (type(path) ~= "string" or path == "" or path:find("%s")
		or path:find("^%.") or path:find("%.$") or path:find("%.%.")) then
		return nil, "override path must be nil or non-empty dot-separated field names"
	end
	if not state.initialized then
		return nil, "DRP must be initialized before runtime overrides can be changed"
	end
	if path == nil then
		return queue_runtime_overrides({})
	end

	local overrides = utils.copy(state.runtime_overrides)
	local keys, parents = {}, {}
	for key in path:gmatch("[^.]+") do
		keys[#keys + 1] = key
	end
	local node = overrides
	for index = 1, #keys - 1 do
		local key = keys[index]
		if type(node[key]) ~= "table" then
			return queue_runtime_overrides(overrides)
		end
		parents[#parents + 1] = { node = node, key = key }
		node = node[key]
	end
	if node[keys[#keys]] ~= nil then
		node[keys[#keys]] = nil
		-- Empty override maps must not mask a scalar default in the profile.
		for index = #parents, 1, -1 do
			if next(node) ~= nil then break end
			local parent = parents[index]
			parent.node[parent.key] = nil
			node = parent.node
		end
	end
	return queue_runtime_overrides(overrides)
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
