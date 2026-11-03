-- Stable equal-size tiles. A point light is allocated atomically as six views.
local M = {}
function M.new(capacity)
	return { capacity = capacity, owners = {}, allocations = {} }
end
function M.release(atlas, id)
	for _, tile in ipairs(atlas.allocations[id] or {}) do atlas.owners[tile] = nil end
	atlas.allocations[id] = nil
end
function M.retain(atlas, selected)
	for id in pairs(atlas.allocations) do if not selected[id] then M.release(atlas, id) end end
end
function M.allocate(atlas, id, count)
	local current = atlas.allocations[id]
	if current and #current == count then return current end
	local free = {}
	for tile = 1, atlas.capacity do
		if not atlas.owners[tile] or atlas.owners[tile] == id then free[#free + 1] = tile end
		if #free == count then break end
	end
	if #free < count then return nil end -- No partial allocation or eviction.
	M.release(atlas, id)
	for _, tile in ipairs(free) do atlas.owners[tile] = id end
	atlas.allocations[id] = free
	return free
end
function M.viewport(tile, size, tile_size)
	local columns = math.floor(size / tile_size)
	return ((tile - 1) % columns) * tile_size, math.floor((tile - 1) / columns) * tile_size, tile_size
end
return M
