local M = {}

local function get_backend()
	local backend = rawget(_G, "drp_native")
	if type(backend) == "table" then
		return backend
	end
	return nil
end

local function require_backend()
	local backend = get_backend()
	if not backend then
		error("DRP native bridge is not available", 3)
	end
	return backend
end

local function native_constant(name, fallback)
	local backend = get_backend()
	local value = backend and backend[name]
	return type(value) == "number" and value or fallback
end

---Native bridge API version expected by this Lua layer.
M.API_VERSION = native_constant("API_VERSION", 1)

---Storage buffer is expected to be rewritten every frame.
M.BUFFER_USAGE_STREAM_DRAW = native_constant("BUFFER_USAGE_STREAM_DRAW", 0)

---Storage buffer is expected to be updated occasionally.
M.BUFFER_USAGE_DYNAMIC_DRAW = native_constant("BUFFER_USAGE_DYNAMIC_DRAW", 1)

---Storage buffer is expected to remain unchanged after creation.
M.BUFFER_USAGE_STATIC_DRAW = native_constant("BUFFER_USAGE_STATIC_DRAW", 2)

---Returns whether the native bridge has been loaded.
---@return boolean available
function M.is_available()
	local backend = get_backend()
	return backend ~= nil and type(backend.get_capabilities) == "function"
end

---Returns GPU features and limits reported by the native graphics context.
---@return table|nil capabilities
---@return string|nil error
function M.get_capabilities()
	local backend = get_backend()
	if not backend or type(backend.get_capabilities) ~= "function" then
		return nil, "DRP native bridge is not available"
	end
	return backend.get_capabilities()
end

---Returns whether the loaded native bridge supports fullscreen submissions.
---@return boolean available
function M.is_fullscreen_available()
	local backend = get_backend()
	return backend ~= nil and type(backend.submit_fullscreen) == "function"
end

---Submits a native fullscreen triangle for the current render-script update.
---The material supplies its render predicate tags; render.draw() draws it later.
---@param material_path string Compiled .materialc resource included by the renderer.
---@return boolean|nil submitted
---@return string|nil error
function M.submit_fullscreen(material_path)
	local backend = get_backend()
	if not backend or type(backend.submit_fullscreen) ~= "function" then
		return nil, "native fullscreen rendering is unavailable"
	end
	return backend.submit_fullscreen(material_path)
end

---Creates a storage buffer. Call only from the render script.
---@param size integer Buffer size in bytes; must be non-zero and four-byte aligned.
---@param usage integer|nil One of the `BUFFER_USAGE_*` constants. Defaults to dynamic.
---@param initial_data string|nil Optional binary string exactly `size` bytes long.
---@return integer handle
function M.create_storage_buffer(size, usage, initial_data)
	return require_backend().create_storage_buffer(size, usage, initial_data)
end

---Replaces a storage buffer allocation and optionally its complete contents.
---@param handle integer
---@param size integer New size in bytes; must be non-zero and four-byte aligned.
---@param usage integer|nil New usage, or nil to retain the previous usage.
---@param data string|nil Optional binary string exactly `size` bytes long.
---@return boolean resized
function M.resize_storage_buffer(handle, size, usage, data)
	return require_backend().resize_storage_buffer(handle, size, usage, data)
end

---Updates an aligned byte range in a storage buffer.
---@param handle integer
---@param offset integer Four-byte-aligned destination offset.
---@param data string Non-empty binary string with four-byte-aligned length.
---@return boolean updated
function M.update_storage_buffer(handle, offset, data)
	return require_backend().update_storage_buffer(handle, offset, data)
end

---Returns a storage buffer's logical size in bytes.
---@param handle integer
---@return integer size
function M.get_storage_buffer_size(handle)
	return require_backend().get_storage_buffer_size(handle)
end

---Binds a storage buffer to a shader descriptor set and binding.
---Call this immediately before the draw or compute dispatch that consumes it.
---@param handle integer
---@param set integer
---@param binding integer
---@return boolean bound
function M.bind_storage_buffer(handle, set, binding)
	return require_backend().bind_storage_buffer(handle, set, binding)
end

---Removes every current binding of a storage buffer.
---@param handle integer
---@return boolean unbound
function M.unbind_storage_buffer(handle)
	return require_backend().unbind_storage_buffer(handle)
end

---Deletes a storage buffer and invalidates its handle.
---@param handle integer
---@return boolean deleted
function M.delete_storage_buffer(handle)
	return require_backend().delete_storage_buffer(handle)
end

---Deletes every storage buffer owned by DRP.
---This is safe when the bridge is unavailable and is called by pipeline finalization.
---@return boolean reset
function M.reset()
	local backend = get_backend()
	if backend and type(backend.reset) == "function" then
		return backend.reset()
	end
	return true
end

return M
