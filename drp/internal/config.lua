local M = {}

function M.string(key, fallback)
	-- Current engines expose typed getters; older SSBO builds used get_config.
	local getter = _G.sys and (sys.get_config_string or sys.get_config)
	if getter then
		local ok, value = pcall(getter, key, fallback)
		if ok and type(value) == "string" and value ~= "" then
			return value
		end
	end
	return fallback
end

function M.boolean(key, fallback)
	local value = M.string(key, fallback and "1" or "0"):lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
end

return M
