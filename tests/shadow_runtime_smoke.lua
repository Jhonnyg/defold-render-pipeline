local M = {}
-- Verifies real light registration, projection math, rendering and cache transitions before exiting.
function M.install(pipeline, ordinary_update)
local native = require("drp.internal.native")
local projections = require("drp.features.shadows.views")
local config = require("drp.features.shadows.config")
local frame = 0
local point_id
local function step(self, dt)
    frame = frame + 1
    if frame == 21 then pipeline.finalize(); msg.post("@system:", "exit", {code=0}); return end
    if frame == 8 then
        for _, light in ipairs(native.get_shadow_lights()) do
            native.update_shadow_light(light.id, {cache = true})
            if light.type == 1 then point_id = light.id end
        end
    elseif frame == 10 then native.invalidate_shadows()
    elseif frame == 12 then native.update_shadow_light(point_id, {softness = 3})
    elseif frame == 14 then native.update_shadow_light(point_id, {enabled = false})
    elseif frame == 16 then native.update_shadow_light(point_id, {enabled = true})
    elseif frame == 17 then assert(pipeline.set_runtime_overrides({shadows={quality="pcss"}}))
    elseif frame == 18 then assert(pipeline.set_runtime_overrides({shadows={quality="pcss_high"}}))
    elseif frame == 19 then assert(pipeline.set_runtime_overrides({shadows={quality="hard"}}))
    end
    ordinary_update(self, dt)
    if frame >= 6 then
        local info = pipeline.get_feature_diagnostics("shadows")
        print("SHADOW_SMOKE", frame, info.available, info.shadowed_lights, info.updated_views, info.cached_views, info.reason)
        assert(info.available, info.reason)
        assert(info.shadowed_lights == ((frame == 14 or frame == 15) and 2 or 3))
        if frame == 6 or frame == 10 then assert(info.updated_views == 9) end
        if frame == 9 or frame == 11 then assert(info.cached_views == 9 and info.updated_views == 0) end
        if frame == 12 or frame == 16 then assert(info.updated_views == 6) end
        if frame == 6 then
            local c = config.resolve({quality="pcf", directional_cascades=2})
            local camera = require("drp.internal.camera").snapshot()
            local lights = native.get_shadow_lights()
            assert(#lights == 3)
            for _, light in ipairs(lights) do
                local maps, splits
                if light.type == 0 then maps, splits = projections.directional(light, camera, c)
                else maps = projections.local_light(light, c) end
                assert(#maps == (light.type == 0 and 2 or light.type == 1 and 6 or 1))
                for _, map in ipairs(maps) do
                    for row=0,3 do for col=0,3 do local v=map.matrix["m"..row..col];assert(v==v and math.abs(v)<math.huge) end end
                    if light.type ~= 0 then
                        local world = vmath.inv(map.view) * vmath.vector4(0,0,-light.range*0.5,1)
                        local projected = map.matrix * world
                        assert(math.abs(projected.x/projected.w)<0.0001 and math.abs(projected.y/projected.w)<0.0001)
                        assert(projected.z/projected.w > -1 and projected.z/projected.w < 1)
                    end
                end
                if splits then assert(splits[1] > camera.near and splits[2] > splits[1]) end
            end
            print("SHADOW_PROJECTIONS_PASS")
        end
    end
    if frame == 20 then
        print("SHADOW_RUNTIME_PASS")
    end
end

    return function(self, dt)
        local ok, err = xpcall(function() step(self, dt) end, debug.traceback)
        if not ok then print("SHADOW_RUNTIME_FAIL", err); msg.post("@system:", "exit", {code=1}) end
    end
end
return M
