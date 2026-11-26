local utils = require("drp.internal.utils")

local M = {}
local Catalog = {}
Catalog.__index = Catalog

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function array(value)
	return type(value) == "table" and (next(value) == nil or utils.is_array(value))
end

local function identifier(value)
	return type(value) == "string" and value:match("^[%a_][%w_]*$") ~= nil
end

local function valid_path(path)
	if type(path) ~= "string" or path == "" or path:find("%.%.") or path:find("^%.") or path:find("%.$") then
		return false
	end
	for part in path:gmatch("[^.]+") do
		if not identifier(part) then
			return false
		end
	end
	return true
end

local function choice(property, value)
	for _, option in ipairs(property.options) do
		if value == option then
			return true
		end
	end
	return false
end

local function raw_value(property, value)
	if property.on_value ~= nil then
		return value and property.on_value or property.off_value
	end
	return value
end

local function read_path(values, path)
	for key in path:gmatch("[^.]+") do
		if type(values) ~= "table" then
			return nil
		end
		values = values[key]
	end
	return values
end

local function write_path(path, value)
	local result, parts = {}, {}
	for key in path:gmatch("[^.]+") do
		parts[#parts + 1] = key
	end
	local parent = result
	for index = 1, #parts - 1 do
		parent[parts[index]] = {}
		parent = parent[parts[index]]
	end
	parent[parts[#parts]] = value
	return result
end

local function remove_path(values, path)
	local parts, parents = {}, {}
	for key in path:gmatch("[^.]+") do
		parts[#parts + 1] = key
	end
	local node = values
	for index = 1, #parts - 1 do
		if type(node[parts[index]]) ~= "table" then
			return
		end
		parents[#parents + 1] = { node = node, key = parts[index] }
		node = node[parts[index]]
	end
	if node[parts[#parts]] == nil then
		return
	end
	node[parts[#parts]] = nil
	for index = #parents, 1, -1 do
		if next(node) ~= nil then
			break
		end
		local parent = parents[index]
		parent.node[parent.key] = nil
		node = parent.node
	end
end

local function validate(property)
	if not identifier(property.key) or #property.key > 63 or not identifier(property.feature) then
		return "feature and property IDs must be identifiers (property ID up to 63 bytes)"
	end
	if not valid_path(property.path) then
		return "path must contain dot-separated setting names"
	end
	if property.diagnostic_key ~= nil and not identifier(property.diagnostic_key) then
		return "diagnostic_key must be an identifier"
	end
	if property.integer ~= nil and type(property.integer) ~= "boolean" then
		return "integer must be a boolean"
	end
	if property.type ~= "boolean" and (property.on_value ~= nil or property.off_value ~= nil) then
		return "on_value/off_value only apply to boolean properties"
	end
	if property.type == "boolean" then
		if type(property.default) ~= "boolean" then
			return "boolean properties need a boolean default"
		end
		if property.on_value ~= nil or property.off_value ~= nil then
			-- Boolean switches can map to a pair of string settings (e.g. a render path).
			if type(property.on_value) ~= "string" or type(property.off_value) ~= "string"
				or property.on_value == property.off_value then
				return "boolean mappings require two distinct strings"
			end
		end
	elseif property.type == "number" then
		if not finite(property.default) then
			return "numeric properties need a finite default"
		end
		local limits = property.limits or {}
		if type(limits) ~= "table" then
			return "limits must be a table"
		end
		for _, key in ipairs({ "min", "max" }) do
			if limits[key] ~= nil and not finite(limits[key]) then
				return "numeric limits must be finite"
			end
		end
		if property.integer and ((limits.min and limits.min % 1 ~= 0) or (limits.max and limits.max % 1 ~= 0)) then
			return "integer property limits must be integral"
		end
		if limits.min and limits.max and limits.min > limits.max then
			return "minimum exceeds maximum"
		end
		if (limits.min and property.default < limits.min) or (limits.max and property.default > limits.max)
			or (property.integer and property.default % 1 ~= 0) then
			return "default is outside the numeric domain"
		end
	elseif property.type == "enum" then
		if not array(property.options) or #property.options == 0 then
			return "enum properties need options"
		end
		local seen = {}
		for _, option in ipairs(property.options) do
			if type(option) ~= "string" or option == "" or seen[option] then
				return "enum options must be unique non-empty strings"
			end
			seen[option] = true
		end
		if not choice(property, property.default) then
			return "enum default must be one of its options"
		end
	else
		return "unsupported property type"
	end

	if property.ui == false then
		return
	end
	local ui = property.ui
	if type(ui) ~= "table" or type(ui.label) ~= "string" or ui.label == "" then
		return "ui needs a label, or must be false"
	end
	if property.type == "number" then
		if not finite(ui.min) or not finite(ui.max) or ui.min >= ui.max then
			return "sliders need finite, increasing min/max values"
		end
		local limits = property.limits or {}
		if (limits.min and ui.min < limits.min) or (limits.max and ui.max > limits.max) then
			return "slider range must lie within the numeric domain"
		end
		if ui.step ~= nil and (not finite(ui.step) or ui.step <= 0) then
			return "slider step must be positive and finite"
		end
		if ui.scale ~= nil and ui.scale ~= "linear" and ui.scale ~= "log" then
			return "slider scale must be linear or log"
		end
		if ui.scale == "log" and ui.min <= 0 then
			return "logarithmic sliders need a positive minimum"
		end
		if property.integer and (ui.min % 1 ~= 0 or ui.max % 1 ~= 0
			or (ui.step and ui.step % 1 ~= 0)) then
			return "integer slider bounds and step must be integral"
		end
	end
end

-- Compile once at pipeline startup, before any feature allocates resources.
-- The registry supplies namespaced IDs; callers only receive defensive copies.
function M.new(descriptors)
	local catalog = setmetatable({ descriptors = {}, by_id = {}, paths = {} }, Catalog)
	for _, source in ipairs(descriptors) do
		local property = utils.copy(source)
		local err = validate(property)
		if err then
			return nil, "property '" .. tostring(property.id) .. "': " .. err
		end
		if catalog.by_id[property.id] then
			return nil, "duplicate property '" .. property.id .. "'"
		end
		for path in pairs(catalog.paths) do
			if path == property.path or path:sub(1, #property.path + 1) == property.path .. "."
				or property.path:sub(1, #path + 1) == path .. "." then
				return nil, "overlapping property paths: " .. path .. " and " .. property.path
			end
		end
		catalog.descriptors[#catalog.descriptors + 1] = property
		catalog.by_id[property.id] = property
		catalog.paths[property.path] = true
	end
	return catalog
end

function Catalog:get_descriptors()
	return utils.copy(self.descriptors)
end

function Catalog:make_override(id, value)
	local property = type(id) == "string" and self.by_id[id] or nil
	if not property then
		return nil, "unknown feature property '" .. tostring(id) .. "'"
	end
	if property.type == "boolean" then
		if type(value) ~= "boolean" then
			return nil, property.id .. " requires a boolean"
		end
	elseif property.type == "number" then
		if not finite(value) then
			return nil, property.id .. " requires a finite number"
		end
		if property.integer then
			value = math.floor(value + 0.5)
		end
		local limits = property.limits or {}
		if limits.min then
			value = math.max(limits.min, value)
		end
		if limits.max then
			value = math.min(limits.max, value)
		end
	elseif not choice(property, value) then
		return nil, property.id .. " requires a supported choice"
	end
	return write_path(property.path, raw_value(property, value))
end

function Catalog:clear_overrides(overrides, paths)
	if overrides ~= nil and type(overrides) ~= "table" then
		return nil, "runtime overrides must be a table"
	end
	if not array(paths) then
		return nil, "property reset paths must be an array"
	end
	for _, path in ipairs(paths) do
		if type(path) ~= "string" or not self.paths[path] then
			return nil, "unknown property reset path"
		end
	end
	local result = utils.copy(overrides or {})
	for _, path in ipairs(paths) do
		remove_path(result, path)
	end
	return result
end

function Catalog:apply_defaults(settings)
	-- Explicit profile/override fields always win, including false values.
	local defaults = {}
	for _, property in ipairs(self.descriptors) do
		utils.merge(defaults, write_path(property.path, raw_value(property, property.default)))
	end
	return utils.merge(defaults, settings)
end

function Catalog:snapshot(settings, overrides)
	local records = self:get_descriptors()
	for _, record in ipairs(records) do
		local value = read_path(settings, record.path)
		if value == nil then
			value = record.default
		elseif record.type == "boolean" then
			if record.on_value ~= nil then
				value = value == record.on_value
			else
				value = value == true
			end
		elseif (record.type == "number" and not finite(value))
			or (record.type == "enum" and not choice(record, value)) then
			value = record.default
		end
		-- Preserve configured numbers outside UI/domain limits. Diagnostics report
		-- the effective value; inspecting settings must never mutate overrides.
		record.value = value
		record.overridden = read_path(overrides, record.path) ~= nil
	end
	return records
end

return M
