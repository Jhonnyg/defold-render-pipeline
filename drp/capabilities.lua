local utils = require("drp.utils")
local native = require("drp.native")

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

local function get_native_capabilities()
	if not native.is_available() then
		return nil
	end
	local ok, result = pcall(native.get_capabilities)
	if ok and type(result) == "table" then
		return result
	end
	return nil
end

---Detects capabilities visible to DRP.
---
---The native provider is merged over the portable Lua baseline when available,
---then explicit overrides are applied last. `nil` means unknown, while `false`
---means explicitly unsupported.
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

	utils.merge(result, get_native_capabilities() or {})
	utils.merge(result, overrides or {})
	-- This is a build constraint, not a device capability. Runtime overrides
	-- cannot restore GPU programs omitted by the compatibility build.
	if _G.sys and sys.get_config and sys.get_config("drp.clustered_resources", "1") == "0" then
		result.features.clustered_resources = false
	end
	result.platform = normalize_platform(result.platform)
	return result
end

function M.normalize_platform(name)
	return normalize_platform(name)
end

return M
