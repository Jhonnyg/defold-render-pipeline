local utils = require("drp.internal.utils")

local M = {}

-- Feature composition is fixed between initialize/finalize. The same registry
-- drives render hooks, properties, diagnostics, and debug views.
local properties = require("drp.internal.properties")
local feature_modules, descriptors, views, view_owners = {}, {}, {}, {}
local catalog = assert(properties.new({}))
local initialized = false

local function array(value)
	return type(value) == "table" and (next(value) == nil or utils.is_array(value))
end

function M.configure(modules)
	if initialized then
		return nil, "feature composition cannot change while DRP is initialized"
	end
	if not array(modules) then
		return nil, "features must be an array of feature modules"
	end
	local selected, names, props, metadata, selected_views, owners = {}, {}, {}, {}, {}, {}
	for _, feature in ipairs(modules) do
		if type(feature) ~= "table" or type(feature.name) ~= "string"
			or not feature.name:match("^[%a_][%w_]*$") or #feature.name > 64 then
			return nil, "each feature needs a name containing an identifier (up to 64 bytes)"
		end
		if names[feature.name] then
			return nil, "duplicate feature '" .. feature.name .. "'"
		end
		if feature.label ~= nil and type(feature.label) ~= "string" then
			return nil, "feature label must be a string"
		end
		for _, hook in ipairs({ "initialize", "finalize", "on_profile_changed", "resize", "begin_frame",
			"render_before_scene", "configure_scene", "prepare_scene", "render_after_scene", "on_message",
			"get_diagnostics", "get_properties", "get_debug_views", "get_debug_source" }) do
			if feature[hook] ~= nil and type(feature[hook]) ~= "function" then
				return nil, feature.name .. "." .. hook .. " must be a function"
			end
		end
		local requirements = feature.requirements or {}
		if not array(requirements) then
			return nil, "feature requirements must be an array"
		end
		for _, requirement in ipairs(requirements) do
			if type(requirement) ~= "string" or requirement == "" then
				return nil, "feature requirements must contain capability names"
			end
		end
		local label = feature.label or feature.name
		metadata[#metadata + 1] = { name = feature.name, label = label, requirements = utils.copy(requirements) }
		names[feature.name] = true
		-- Copy the hook table to freeze membership without copying feature-owned state.
		local registered = {}
		for key, value in pairs(feature) do
			registered[key] = value
		end
		selected[#selected + 1] = registered

		local feature_properties = {}
		if feature.get_properties then
			feature_properties = feature.get_properties()
		end
		if not array(feature_properties) then
			return nil, feature.name .. ".get_properties() must return an array"
		end
		for _, descriptor in ipairs(feature_properties) do
			if type(descriptor) ~= "table" then
				return nil, feature.name .. " properties must be tables"
			end
			local property = utils.copy(descriptor)
			property.key = property.id
			property.id = feature.name .. "." .. tostring(property.key)
			property.feature, property.feature_label = feature.name, label
			if property.ui == nil then
				property.ui = { label = tostring(property.key) }
			end
			props[#props + 1] = property
		end
		local feature_views = {}
		if feature.get_debug_views then
			feature_views = feature.get_debug_views()
		end
		if not array(feature_views) then
			return nil, feature.name .. ".get_debug_views() must return an array"
		end
		for _, descriptor in ipairs(feature_views) do
			if type(descriptor) ~= "table" or type(descriptor.id) ~= "string"
				or descriptor.id:sub(1, #feature.name + 1) ~= feature.name .. "."
				or (descriptor.kind ~= "scene" and descriptor.kind ~= "texture")
				or type(descriptor.label) ~= "string" then
				return nil, feature.name .. " has an invalid debug view descriptor"
			end
			if owners[descriptor.id] then
				return nil, "duplicate debug view '" .. descriptor.id .. "'"
			end
			local view = utils.copy(descriptor)
			view.feature = feature.name
			selected_views[#selected_views + 1] = view
			owners[view.id] = registered
		end
	end
	local compiled, err = properties.new(props)
	if not compiled then
		return nil, err
	end
	-- Publish only after validating the entire list. A bad custom schema cannot
	-- leave half a registry active or allocate any GPU resources.
	feature_modules, descriptors = selected, metadata
	views, view_owners, catalog = selected_views, owners, compiled
	return true
end

function M.get_features()
	return utils.copy(descriptors)
end

function M.get_properties()
	return catalog:get_descriptors()
end

function M.property_snapshot(settings, overrides)
	return catalog:snapshot(settings, overrides)
end

function M.make_property_override(id, value)
	return catalog:make_override(id, value)
end

function M.clear_property_overrides(overrides, paths)
	return catalog:clear_overrides(overrides, paths)
end

function M.apply_defaults(settings)
	return catalog:apply_defaults(settings)
end

function M.is_supported(name, capabilities)
	for _, feature in ipairs(descriptors) do
		if feature.name == name then
			local supported = capabilities and capabilities.features or {}
			for _, requirement in ipairs(feature.requirements) do
				if supported[requirement] == false
					or (capabilities and capabilities.strict and supported[requirement] ~= true) then
					return false, "Unavailable capability: " .. requirement
				end
			end
			return true
		end
	end
	return false, "feature is not included in this pipeline"
end

local function invoke(hook_name, context, ...)
	for _, feature in ipairs(feature_modules) do
		local hook = feature[hook_name]
		if hook then
			hook(context, ...)
		end
	end
end

function M.initialize(context)
	initialized = true
	invoke("initialize", context)
end

function M.on_profile_changed(context, transition)
	invoke("on_profile_changed", context, transition)
end

function M.resize(context, width, height)
	invoke("resize", context, width, height)
end

function M.begin_frame(context)
	invoke("begin_frame", context)
end

function M.render_before_scene(context)
	invoke("render_before_scene", context)
end

function M.configure_scene(context, pass)
	invoke("configure_scene", context, pass)
end

function M.prepare_scene(context, pass)
	invoke("prepare_scene", context, pass)
end

function M.render_after_scene(context, pass)
	invoke("render_after_scene", context, pass)
end

function M.on_message(context, message_id, message, sender)
	invoke("on_message", context, message_id, message, sender)
end

function M.get_diagnostics(name)
	for _, feature in ipairs(feature_modules) do
		if feature.name == name and feature.get_diagnostics then
			return feature.get_diagnostics()
		end
	end
	return nil
end

function M.get_debug_views()
	return utils.copy(views)
end

function M.get_debug_source(context, id)
	local feature = view_owners[id]
	if not feature then
		return nil, "unknown debug view '" .. tostring(id) .. "'"
	end
	if not feature.get_debug_source then
		return nil, "feature does not provide a debug source"
	end
	return feature.get_debug_source(context, id)
end

function M.finalize(context)
	for index = #feature_modules, 1, -1 do
		local hook = feature_modules[index].finalize
		if hook then
			hook(context)
		end
	end
	initialized = false
	M.configure({})
end

return M
