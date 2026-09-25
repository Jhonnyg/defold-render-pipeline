local capabilities = require("drp.capabilities")
local utils = require("drp.utils")
local clustered_requirements = require("drp.features.clustered.requirements")

local M = {}

local registry = {}
local resolved_cache = {}

local ALLOWED_PROFILE_KEYS = {
	description = true,
	extends = true,
	fallback = true,
	name = true,
	platform_overrides = true,
	requirements = true,
	settings = true,
}

local function validate_name(name)
	return type(name) == "string" and name:match("^[a-z][a-z0-9_%-]*$") ~= nil
end

local function validate_profile(name, profile)
	if not validate_name(name) then
		return nil, "profile name must start with a lowercase letter and contain only lowercase letters, numbers, '_' or '-'"
	end
	if type(profile) ~= "table" then
		return nil, "profile '" .. name .. "' must be a table"
	end
	for key in pairs(profile) do
		if not ALLOWED_PROFILE_KEYS[key] then
			return nil, "profile '" .. name .. "' contains unknown field '" .. tostring(key) .. "'"
		end
	end
	if profile.name ~= nil and profile.name ~= name then
		return nil, "profile field 'name' must match the registered name '" .. name .. "'"
	end
	if profile.extends ~= nil and not validate_name(profile.extends) then
		return nil, "profile '" .. name .. "' has an invalid extends value"
	end
	if profile.fallback ~= nil and not validate_name(profile.fallback) then
		return nil, "profile '" .. name .. "' has an invalid fallback value"
	end
	if profile.settings ~= nil and type(profile.settings) ~= "table" then
		return nil, "profile '" .. name .. "' settings must be a table"
	end
	if profile.requirements ~= nil then
		if type(profile.requirements) ~= "table" or (next(profile.requirements) ~= nil and not utils.is_array(profile.requirements)) then
			return nil, "profile '" .. name .. "' requirements must be an array"
		end
		for _, requirement in ipairs(profile.requirements) do
			if type(requirement) ~= "string" or requirement == "" then
				return nil, "profile '" .. name .. "' contains an invalid capability requirement"
			end
		end
	end
	if profile.platform_overrides ~= nil and type(profile.platform_overrides) ~= "table" then
		return nil, "profile '" .. name .. "' platform_overrides must be a table"
	end
	return true
end

local function resolve_definition(name, stack)
	if resolved_cache[name] then
		return utils.copy(resolved_cache[name])
	end

	local source = registry[name]
	if not source then
		return nil, "unknown quality profile '" .. tostring(name) .. "'"
	end

	stack = stack or {}
	if stack[name] then
		return nil, "quality profile inheritance cycle at '" .. name .. "'"
	end
	stack[name] = true

	local resolved = {
		name = name,
		description = source.description,
		fallback = source.fallback,
		requirements = {},
		settings = {},
		platform_overrides = {},
	}

	if source.extends then
		local parent, err = resolve_definition(source.extends, stack)
		if not parent then
			stack[name] = nil
			return nil, err
		end
		resolved.description = source.description or parent.description
		resolved.fallback = source.fallback or parent.fallback
		resolved.requirements = utils.copy(parent.requirements)
		resolved.settings = utils.copy(parent.settings)
		resolved.platform_overrides = utils.copy(parent.platform_overrides)
	end

	if source.requirements then
		resolved.requirements = utils.copy(source.requirements)
	end
	utils.merge(resolved.settings, source.settings or {})
	utils.merge(resolved.platform_overrides, source.platform_overrides or {})

	stack[name] = nil
	resolved_cache[name] = utils.copy(resolved)
	return resolved
end

local function apply_platform_override(profile, platform)
	local override = profile.platform_overrides[platform] or profile.platform_overrides.default
	if not override then
		return profile
	end
	if override.settings then
		utils.merge(profile.settings, override.settings)
	else
		utils.merge(profile.settings, override)
	end
	if override.requirements then
		profile.requirements = utils.copy(override.requirements)
	end
	return profile
end

local function missing_requirements(profile, detected)
	local missing = {}
	local features = detected.features or {}
	local checked = {}
	for _, requirement in ipairs(profile.requirements) do
		checked[requirement] = true
		local value = features[requirement]
		if value == false or (detected.strict and value ~= true) then
			missing[#missing + 1] = requirement
		end
	end
	if profile.settings.rendering and profile.settings.rendering.path == "forward_plus" then
		-- Custom profiles and runtime path overrides cannot omit the core GPU
		-- requirements merely by leaving them out of the profile's list.
		for _, name in ipairs({ "compute_shaders", "storage_buffers" }) do
			local value = features[name]
			if not checked[name] and (value == false or (detected.strict and value ~= true)) then
				missing[#missing + 1] = name
			end
		end
		for _, reason in ipairs(clustered_requirements.missing_limits(detected)) do
			missing[#missing + 1] = reason
		end
		if features.clustered_resources == false then
			missing[#missing + 1] = "clustered resources are excluded from this build"
		end
	end
	return missing
end

function M.register(name, profile)
	local ok, err = validate_profile(name, profile)
	if not ok then
		return nil, err
	end
	local stored = utils.copy(profile)
	stored.name = name
	registry[name] = stored
	resolved_cache = {}
	return true
end

function M.unregister(name)
	if not registry[name] then
		return false
	end
	registry[name] = nil
	resolved_cache = {}
	return true
end

function M.get(name)
	return resolve_definition(name)
end

function M.get_names()
	local names = {}
	for name in pairs(registry) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

---Resolves a requested profile, including inheritance, platform overrides, and
---the profile fallback chain.
---@param requested string
---@param detected table
---@param settings_overrides table|nil Settings applied before requirement validation.
---@return table|nil, string|nil
function M.resolve(requested, detected, settings_overrides)
	detected = detected or capabilities.detect()
	local attempted = {}
	local reasons = {}
	local candidate = requested

	while candidate do
		if attempted[candidate] then
			return nil, "quality profile fallback cycle at '" .. candidate .. "'"
		end
		attempted[candidate] = true

		local profile, err = resolve_definition(candidate)
		if not profile then
			return nil, err
		end
		apply_platform_override(profile, detected.platform or "unknown")
		utils.merge(profile.settings, settings_overrides or {})

		local missing = missing_requirements(profile, detected)
		if #missing == 0 then
			return {
				requested = requested,
				effective = candidate,
				profile = profile,
				reasons = reasons,
			}
		end

		reasons[#reasons + 1] = string.format(
			"profile '%s' has unavailable requirements: %s",
			candidate,
			utils.join(missing, ", ")
		)
		candidate = profile.fallback
	end

	return nil, "no supported fallback exists for quality profile '" .. requested .. "': " .. utils.join(reasons, "; ")
end

function M.with_settings_overrides(resolution, overrides)
	local result = utils.copy(resolution)
	utils.merge(result.profile.settings, overrides or {})
	return result
end

-- Keep these as explicit requires. Defold's build-time Lua dependency scanner
-- cannot discover modules loaded by passing a variable to require(), and would
-- otherwise omit the built-in profiles from the bundle.
local BUILTIN_PROFILES = {
	require("drp.profiles.compatibility"),
	require("drp.profiles.balanced"),
	require("drp.profiles.high"),
	require("drp.profiles.ultra"),
}

for _, profile in ipairs(BUILTIN_PROFILES) do
	local ok, err = M.register(profile.name, profile)
	assert(ok, err)
end

return M
