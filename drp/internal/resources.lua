local utils = require("drp.internal.utils")

local M = {}

local declarations = {}

---Declares a named pipeline resource without allocating it.
---
---This registry establishes ownership and dependency contracts for future
---render features. GPU resource creation will be implemented in a later
---milestone.
---@param name string
---@param descriptor table
---@return boolean|nil, string|nil
function M.declare(name, descriptor)
	if type(name) ~= "string" or name == "" then
		return nil, "resource name must be a non-empty string"
	end
	if type(descriptor) ~= "table" then
		return nil, "resource descriptor must be a table"
	end
	if declarations[name] then
		return nil, "resource '" .. name .. "' is already declared"
	end
	declarations[name] = utils.copy(descriptor)
	return true
end

function M.remove(name)
	if not declarations[name] then
		return false
	end
	declarations[name] = nil
	return true
end

function M.get(name)
	return declarations[name] and utils.copy(declarations[name]) or nil
end

function M.get_names()
	local names = {}
	for name in pairs(declarations) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

function M.reset()
	declarations = {}
end

return M
