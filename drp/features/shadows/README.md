# Shadows

This feature currently provides lifecycle and configuration scaffolding. It is
registered before clustered scene rendering, with HDR presentation afterward.
It does not allocate GPU resources, register lights, or render shadows yet.

## Configuration and diagnostics

The feature observes `profile.settings.shadows`, including inherited values,
platform overrides and runtime overrides. Requests become active at the normal
pipeline frame boundary. Existing profile values such as `quality`,
`directional_cascades`, and `max_shadowed_local_lights` remain future intent.

```lua
local drp = require("drp.drp")

local shadows = drp.get_feature_diagnostics("shadows")
print(shadows.settings.quality) -- requested quality from the active profile
print(shadows.available)       -- false until rendering is implemented
print(shadows.reason)

-- Queued until the next pipeline frame, like other settings overrides:
assert(drp.set_runtime_overrides({ shadows = { enabled = false } }))
-- Restore the profile's shadow settings:
assert(drp.clear_runtime_overrides("shadows"))
```

The diagnostics record contains:

| Field | Meaning |
| --- | --- |
| `initialized` | Whether the feature has been initialized by the pipeline. |
| `enabled` | Requested participation: explicit `enabled = true` or a nonempty quality other than `off`. Explicit `enabled = false` or `quality = "off"` disables it. |
| `available` | Always `false` in this scaffold, regardless of device capabilities. |
| `effective_quality` | Always `"off"` until shadow rendering exists. |
| `reason` | `"not initialized"`, `"disabled by settings"`, or `"shadow rendering is not implemented"`. |
| `settings` | A defensive copy of the active profile's shadow settings; these are requested, not validated or effective GPU budgets. |

Finalization clears the requested settings so reinitialization cannot retain
old overrides. The scaffold works without a render runtime or native bridge,
including in compatibility exports. It imposes no new capability requirements.

## Next implementation steps

- Add the companion `shadow_caster.script` authoring adapter and context-owned
  registration once the native-light identity/index contract is settled.
- Add per-frame light data, atlas allocation and dirty-view rendering here;
  declare concrete resource ownership when those resources are implemented.
- Add shadow visibility to clustered PBR, then soft filtering, cache tracking
  and diagnostics for the actual rendering work.

The companion script is not supplied as an inert component. Users should keep
their existing scenes unchanged until light registration is implemented. This
scaffold adds no engine API, shadow material, atlas format or cache policy.
