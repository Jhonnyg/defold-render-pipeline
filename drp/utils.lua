local M = {}

---Creates a deep copy of a value.
---
---Table keys and values are copied recursively. Cycles and shared table
---references are preserved in the resulting object graph.
---@param value any
---@param seen table|nil Internal table used while traversing cyclic values.
---@return any
function M.copy(value, seen)
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
		result[M.copy(key, seen)] = M.copy(child, seen)
	end
	return result
end

---Returns whether a value is a non-empty, contiguous one-based array.
---@param value any
---@return boolean
function M.is_array(value)
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false
		end
		count = count + 1
	end
	for index = 1, count do
		if value[index] == nil then
			return false
		end
	end
	return count > 0
end

---Deep-merges source fields into a destination table.
---
---Map-like tables are merged recursively. Arrays and scalar values replace
---the destination value and are defensively copied.
---@param destination table
---@param source table|nil
---@return table destination
function M.merge(destination, source)
	for key, value in pairs(source or {}) do
		if type(value) == "table" and type(destination[key]) == "table" and not M.is_array(value) then
			M.merge(destination[key], value)
		else
			destination[key] = M.copy(value)
		end
	end
	return destination
end

---Joins array values after converting each value to a string.
---@param values any[]
---@param separator string|nil
---@return string
function M.join(values, separator)
	local parts = {}
	for index, value in ipairs(values) do
		parts[index] = tostring(value)
	end
	return table.concat(parts, separator)
end

return M
