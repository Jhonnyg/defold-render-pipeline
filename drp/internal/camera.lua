local M = {}

-- Depth reconstruction and scene shading must use the same camera for a frame.
-- Match Defold's existing last-enabled-camera selection in the clustered path.
function M.snapshot()
	if not _G.camera then
		return nil
	end

	local cameras = camera.get_cameras()
	for index = #cameras, 1, -1 do
		local component = cameras[index]
		if camera.get_enabled(component) then
			return {
				component = component,
				view = camera.get_view(component),
				projection = camera.get_projection(component),
				near = camera.get_near_z(component),
				far = camera.get_far_z(component),
			}
		end
	end
end

return M
