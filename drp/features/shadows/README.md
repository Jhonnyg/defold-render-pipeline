# Shadows

DRP provides shadow maps for directional, point and spot lights on the clustered
rendering path. Opaque models and alpha-tested models cast shadows; clustered
opaque, masked and transparent materials receive them. Shadow visibility affects
each light's direct diffuse/specular contribution, preserving ambient and emissive
lighting. Shadows are applied before HDR tone mapping.

## Setup

1. Use an engine/SDK containing `CompLightGetLightInstance()` and
   `GetLightInstanceRenderData()` and build the DRP native extension with it.
2. Select `/drp/drp.render` and a clustered profile (`balanced`, `high`, `ultra`).
3. Add `/drp/features/shadows/shadow_caster.script` beside each light that should
   produce shadows. Its `light` URL defaults to `#light`; select another component
   URL when necessary. One registration is allowed per light.
4. Use DRP clustered materials for shadow receivers. No script is needed on
   individual models. Conventional `model`-tagged geometry casts opaque shadows
   but retains its conventional, unshadowed shading when receiving light.

The script selects a **light**, despite its `shadow_caster` name. It registers a
versioned light handle during `init()` and unregisters during `final()`. Every
render update resolves the handle to the engine's current light-buffer index.
Disabled, unsubmitted, deleted and ambient lights cannot leave a usable shadow
entry behind. The extension owns registrations in `DRPContext`, so separate game
and render Lua worlds share them.

See [the moving three-light example](../../../examples/shadows/README.md).
All materials needed for shadow-map rendering are dependencies of `drp.render`.
No fullscreen game object or extra bootstrap collection is required.

## Light properties

| Property | Default | Meaning |
| --- | --- | --- |
| `light` | `#light` | Light component URL, resolved at initialization; recreate the script to change the target. |
| `enabled` | `true` | Whether this light participates in shadow selection. |
| `priority` | `0` | Higher priorities win atlas residency and update work. |
| `bias` | `0.001` | Constant comparison bias in normalized shadow depth, 0–0.1. |
| `normal_bias` | `0.02` | Receiver offset along the world-space shading normal, in scene units, 0–100. |
| `softness` | `1.5` | Filter/search radius in shadow-map texels, 0–8. Zero selects a single comparison. |
| `cache` | `false` | Reuse depth maps while projections and the explicit geometry revision remain unchanged. |

Properties other than `light` can be changed using `go.set()` on the companion
script. It synchronizes them on its next update. `invalidate_shadows` can also be
posted to the companion script to invalidate all cached geometry.

## Quality and budgets

Settings merge through the normal runtime override API and activate at a frame
boundary:

```lua
local drp = require("drp.drp")
assert(drp.set_runtime_overrides({ shadows = {
    quality = "pcf",
    max_shadowed_local_lights = 4,
    directional_cascades = 2,
    max_updates_per_frame = 16,
    distance = 100,
} }))
-- Restore the selected profile's settings:
assert(drp.clear_runtime_overrides("shadows"))
```

| Setting | Default / bounds |
| --- | --- |
| `enabled` | Enabled for recognized qualities, unless explicitly false. |
| `quality` | Profile-selected: `off`, `hard`, `pcf`, `pcss`, `pcss_high`. |
| `atlas_size` / `tile_size` | Local atlas 2048 / 256; at most 64 tiles. |
| `directional_atlas_size` / `directional_tile_size` | Directional atlas 2048 / 1024; at most 16 tiles. |
| `max_shadowed_local_lights` | Balanced 4, high 12, ultra 24; HTML5 balanced 2. Actual residency is also tile-limited. |
| `max_shadowed_directional_lights` | 1; configurable 0–4. |
| `directional_cascades` | Balanced 2, high/ultra 4; configurable 1–4. |
| `max_updates_per_frame` | Balanced 32, high 64, ultra 80 views; configurable 0–128. A point update needs at least 6. |
| `distance` | 100 scene units; directional shadow distance, capped by camera far plane. |
| `caster_distance` | 100 scene units; extra light-space depth for off-camera directional casters. |
| `split_lambda` | 0.6, clamped 0–1; logarithmic/uniform cascade split mix. |
| `cascade_blend` | 0.1, clamped 0–0.3; overlap/blend fraction, with final distance fade. |

Atlas dimensions are clamped to reported texture/framebuffer limits and 4096.
At default tile sizes the local atlas fits ten point lights (six tiles each), or
64 spots, before the profile's light limit is applied. A directional light uses
one tile per cascade. Raising the light limit alone does not allocate more tiles.

`pcf` uses 16 fixed disk comparisons. `pcss` adds eight blocker-search samples
and a bounded contact-hardening radius; `pcss_high` uses 32 filter comparisons.
This is an approximation with a texel-radius cap, not a physical area-light
model. Point views overlap and filter taps are clamped within their own tile.
Directional cascades use sphere fitting, texel snapping and overlap blending.

Atlas tiles have stable ownership and are cleared individually using a native
fullscreen triangle. A point light gets all six tiles/updates or none. Equal
priority lights rotate through update work when its budget is tight. Lights
whose dirty maps cannot be updated are unshadowed for that frame; stale maps are
never published as if current. Strict priorities may starve lower-priority work.

## Caching

The default redraws selected lights each frame, including animated geometry.
Use `cache=true` only when the application can explicitly report geometry changes:

```lua
-- After moving/creating/deleting a cached occluder, changing animation, alpha
-- coverage, material visibility, or loading/unloading geometry:
assert(drp.invalidate_shadows())
```

Light projection changes automatically invalidate that light's maps. Camera
changes invalidate affected directional cascades. Point and spot maps can survive
camera motion. Changes to compact light-buffer indices rebuild metadata without
redrawing valid maps. The engine's `m_BufferRevision` checks snapshot consistency;
it is deliberately not a depth-map cache key.

DRP does not yet observe every model transform/animation/material change. The
explicit invalidation call updates a shared native revision, including when game
and render scripts use separate Lua worlds. It currently invalidates all cached
lights, not only those intersecting the changed model.

## Resources and diagnostics

Atlases prefer sampleable R32F color plus a depth attachment, falling back to
RGBA32F when R32F is unavailable. Manual depth comparisons avoid relying on
backend-specific comparison samplers. Two default R32F atlases use about 64 MiB
including 32-bit depth; RGBA32F uses about 160 MiB. Metadata uses 15 KiB at
SSBO set 2, binding 6. The shader supports the existing 64-light engine buffer.

```lua
local info = drp.get_feature_diagnostics("shadows")
print(info.available, info.reason, info.effective_quality)
print(info.shadowed_lights, info.updated_views, info.cached_views)
print(info.deferred_views, info.dropped_lights, info.atlas_bytes)
```

`settings` is a defensive copy of the request; `budgets` holds the validated
configuration. `registered_lights` counts active lights returned by the engine
snapshot. Deferred views lack this frame's update budget; dropped lights lack
residency or a supported projection/index. Allocation/submission/draw failures
fail closed and retry; diagnostics report the failure. The renderer restores
camera, viewport and drawing state before the clustered/HDR scene pass.

Compatibility rendering has shadows off. Transparent surfaces receive shadows
but do not cast translucent shadows. Custom deformation must be reproduced by
the shadow vertex pass. Alpha masking uses the same asset-pbr coverage/cutoff as
the visible pass. Directional cameras need positive near/far depths. Multiple
scene cameras are not rendered concurrently; the last enabled camera is shared
with clustered lighting.

This implementation does not raise the engine/clustered light capacity to 256.
Hundreds of moving models can cast into selected lights, subject to draw cost;
256 simultaneously shadowed lights needs a separate light-buffer, residency and
performance work item.
