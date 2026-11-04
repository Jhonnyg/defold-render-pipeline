local M = {}
-- One camera snapshot is shared by shadow cascades and clustered assignment.
function M.snapshot()
	if not _G.camera then
		return nil
	end
	local cameras = camera.get_cameras()
	for i = #cameras, 1, -1 do
		local component = cameras[i]
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
