local M = {}

-- DRP owns the feature set. Add built-in feature modules here in execution
-- order as they are implemented.
local feature_modules = {
	require("drp.features.clustered.clustered"),
}

local function invoke(hook_name, context, ...)
	for _, feature in ipairs(feature_modules) do
		local hook = feature[hook_name]
		if hook then
			hook(context, ...)
		end
	end
end

function M.initialize(context)
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

function M.render(context)
	invoke("render", context)
end

function M.get_diagnostics(name)
	for _, feature in ipairs(feature_modules) do
		if feature.name == name and feature.get_diagnostics then
			return feature.get_diagnostics()
		end
	end
	return nil
end

function M.finalize(context)
	for index = #feature_modules, 1, -1 do
		local hook = feature_modules[index].finalize
		if hook then
			hook(context)
		end
	end
end

return M
