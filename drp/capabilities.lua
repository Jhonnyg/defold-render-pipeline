local M = {}

local PLATFORM_ALIASES = {
	android = "android",
	darwin = "macos",
	html5 = "html5",
	ios = "ios",
	iphoneos = "ios",
	linux = "linux",
	macos = "macos",
	web = "html5",
	windows = "windows",
}

local function copy(value, seen)
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local result = {}
	seen[value] = result
	for key, child in pairs(value) do
		result[copy(key, seen)] = copy(child, seen)
	end
	return result
end

local function merge(destination, source)
	for key, value in pairs(source or {}) do
		if type(value) == "table" and type(destination[key]) == "table" then
			merge(destination[key], value)
		else
			destination[key] = copy(value)
		end
	end
	return destination
end

local function normalize_platform(name)
	name = tostring(name or "unknown"):lower()
	return PLATFORM_ALIASES[name] or name
end

local function get_system_info()
	if _G.sys and sys.get_sys_info then
		local ok, info = pcall(sys.get_sys_info)
		if ok and type(info) == "table" then
			return info
		end
	end
	return {}
end

---Detects capabilities visible to the Lua layer.
---
---GPU feature fields intentionally remain nil until a native capability
---provider is added. `nil` means unknown, while `false` means explicitly
---unsupported. Quality resolution can be made strict to treat unknown values
---as unsupported.
---@param overrides table|nil
---@return table
function M.detect(overrides)
	local system_info = get_system_info()
	local result = {
		platform = normalize_platform(system_info.system_name),
		source = "lua-baseline",
		strict = false,
		features = {
			compute_shaders = nil,
			storage_buffers = nil,
			float_render_targets = nil,
			sampleable_depth = nil,
			timestamp_queries = nil,
		},
		limits = {},
	}

	merge(result, overrides or {})
	result.platform = normalize_platform(result.platform)
	return result
end

function M.copy(value)
	return copy(value)
end

function M.normalize_platform(name)
	return normalize_platform(name)
end

return M
