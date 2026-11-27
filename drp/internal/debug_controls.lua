local features = require("drp.internal.features")

local M = {}

-- Project feature composition is selected at initialization, not require-time.
-- Translate general properties into the small, plain-data GUI message format.
local function control(property)
	if property.ui == false then
		return nil
	end
	local ui = property.ui
	return {
		id = property.id, feature = property.feature, feature_label = property.feature_label,
		path = property.path, label = ui.label,
		kind = property.type == "enum" and "choice" or property.type,
		default = property.default, diagnostic_key = property.diagnostic_key,
		min = ui.min, max = ui.max, step = ui.step, scale = ui.scale,
		integer = property.integer, options = property.options,
		value = property.value, overridden = property.overridden,
	}
end

function M.get_descriptors()
	local controls = {}
	for _, property in ipairs(features.get_properties()) do
		local descriptor = control(property)
		if descriptor then
			controls[#controls + 1] = descriptor
		end
	end
	return controls
end

function M.make_override(id, value)
	for _, descriptor in ipairs(M.get_descriptors()) do
		if descriptor.id == id then
			-- Interactive edits stay within the slider range. Other property
			-- consumers use the property's numeric domain instead of UI limits.
			if descriptor.kind == "number" and type(value) == "number"
				and value == value and math.abs(value) < math.huge then
				value = math.max(descriptor.min, math.min(descriptor.max, value))
			end
			return features.make_property_override(id, value)
		end
	end
	return nil, "unknown debug control '" .. tostring(id) .. "'"
end

function M.get_paths(feature)
	local paths = {}
	for _, descriptor in ipairs(M.get_descriptors()) do
		if descriptor.feature == feature then
			paths[#paths + 1] = descriptor.path
		end
	end
	if #paths == 0 then
		return nil, "unknown debug feature '" .. tostring(feature) .. "'"
	end
	return paths
end

function M.clear_overrides(overrides, paths)
	return features.clear_property_overrides(overrides, paths)
end

function M.snapshot(settings, overrides)
	local records = {}
	for _, property in ipairs(features.property_snapshot(settings, overrides)) do
		local descriptor = control(property)
		if descriptor then
			records[#records + 1] = descriptor
		end
	end
	return records
end

return M
