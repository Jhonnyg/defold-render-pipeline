# Screen-space ambient occlusion (GTAO)

Select `/drp/drp.render` and use DRP opaque/masked glTF materials (or the
conventional opaque `model` path). Balanced, high and ultra enable GTAO
automatically. No scene helper, shadow feature or new engine API is required.
HDR is optional. Compatibility defaults to AO off, but supports opting in on
devices with the required floating-point render targets.

```lua
local drp = require("drp.drp")

assert(drp.set_runtime_overrides({
    post = {
        gtao = true,
        gtao_radius = 0.5,       -- Scene units; match the scale of your models.
        gtao_intensity = 1.0,
        gtao_quality = "high",
    },
}))

-- Disable AO for comparison. Other overrides remain in effect.
assert(drp.set_runtime_overrides({ post = { gtao = false } }))
-- Restore the profile's AO switch.
assert(drp.clear_runtime_overrides("post.gtao"))

local ao = drp.get_feature_diagnostics("gtao")
print(ao.available, ao.reason, ao.raw_width, ao.raw_height)
```

AO only attenuates ambient/indirect lighting. A scene illuminated entirely by
direct lights may show little difference. Material occlusion and GTAO multiply
the built-in composition's diffuse and specular indirect visibility; direct
lights, emission and unlit colors retain their existing behavior. This initial
specular treatment is scalar visibility, not directional specular occlusion.

## Debugging the result

Sponza includes the shared [debug overlay](../../debug/README.md). Press **F2**
once for filtered AO, again for raw AO, and again for the scene depth used by AO.
**F3** moves backwards, **F4** restores scene shading, and **F1** hides the panel
without changing the selected view. White AO pixels are unoccluded; dark pixels
show ambient occlusion. The views bypass display tone mapping, so exposure does
not change the displayed visibility values.

Look at pedestal bases, columns meeting the floor, and wall-floor corners. Raw
AO reveals sampling noise before filtering; depth reveals missing geometry or
incorrect silhouettes. Depth is logarithmic: distant surfaces are brighter and
background is black. Normal-map grooves do not appear in the depth prepass.
If AO is disabled or unavailable, the panel reports the reason rather than
showing an old texture. Selecting a view does not enable AO or alter its settings.

## Settings

All keys are under `post`. Changes activate at the next frame boundary.

| Key | Default | Meaning |
| --- | --- | --- |
| `gtao` | Profile dependent | Enable screen-space AO. |
| `gtao_resolution` | `0.5` | Raw AO size relative to the viewport, clamped to 0.25–1. Depth and final visibility remain full resolution. |
| `gtao_quality` | `"medium"` | `low`, `medium`, `high`, or `ultra`; invalid names use medium. |
| `gtao_radius` | `0.5` | World/view-space search radius, clamped to 0.001–1,000,000. |
| `gtao_intensity` | `1.0` | Occlusion strength, clamped to 0–4. Zero gives unoccluded output. |
| `gtao_power` | `1.0` | Visibility contrast exponent, clamped to 0.1–4. |
| `gtao_bias` | `0.02` | Dimensionless horizon-cosine offset to reduce self-occlusion, clamped to 0–0.25. |

Quality budgets use 2×4, 3×6, 4×8 and 6×8 slices×steps respectively. Each slice
searches in both directions. Balanced uses medium; high and ultra increase the
sample count while retaining half resolution. Radius projection is limited to
128 full-resolution depth pixels to bound large near-camera searches.

## Passes and resources

1. Snapshot the last enabled camera once for depth reconstruction and shading.
2. Render opaque and alpha-masked surfaces into full-resolution R32F linear
   depth (`-view_position.z`). A separate hardware depth attachment selects the
   nearest surface. Zero marks background. Coverage and sidedness use the same
   built-in glTF sampling helper as the color pass.
3. Reconstruct positions and geometric normals from depth. Search paired
   horizons in each slice and analytically integrate visibility using GTAO's
   cosine-weighted arc integral. Screen-stable rotation reduces sampling bands.
4. Bilaterally filter and upsample raw RGBA8 visibility into a full-resolution
   RGBA8 target, rejecting incompatible depths at silhouettes.
5. Bind the visibility texture during scene shading, before optional HDR tone
   mapping. Transparent surfaces neither contribute depth nor receive GTAO.

The analytic integration follows [Jimenez et al., Practical Real-Time
Strategies for Accurate Indirect Occlusion, section 4.1](https://www.activision.com/cdn/research/Practical_Real_Time_Strategies_for_Accurate_Indirect_Occlusion_NEW%20VERSION_COLOR.pdf).
The old experiment supplied the depth/prepass structure and spatial-filtering
approach; its horizon-cosine averaging has been replaced by the analytic slice
integral. No external AO library is required.

The native fullscreen bridge supplies both passes. Their materials and depth
overrides are explicit dependencies of both `.render` resources, so they are
included in bundles without scene objects. All fullscreen entries are submitted
before the first draw each frame. Targets are reused until size/resolution
changes and released when disabled or finalized.

## Scene integration

The pipeline schedules GTAO through the [shared scene stages](../../internal/README.md).
`begin_frame` prepares targets and submits both fullscreen entries.
`render_before_scene` produces depth, raw visibility and filtered visibility.
`configure_scene` contributes the projection and visibility constants, the named
`drp_ao_texture` binding, and a request for the conventional model material
override. Disabled or unavailable frames supply neutral visibility constants
and omit the texture binding, preserving other features' contributions.

The shared scene renderer applies these inputs to opaque and masked shading
and owns their binding lifetime. Clustered lighting contributes its own
constants and storage buffers independently; HDR contributes its output target
and resolves after scene completion. GTAO resource allocation and fallback
remain local to this feature.

## Availability and limitations

GTAO requires an enabled camera with a positive near/far depth range, native
fullscreen submission, R32F color-target support and six fragment texture slots
for the five glTF textures plus AO. It works with perspective and orthographic
projections whose visible depth range is positive. The cluster heatmap bypasses
AO. Unknown float-target support is tried in non-strict mode; strict mode
requires confirmed support and a known sufficient texture-stage limit.

Failure disables AO independently of the lighting/HDR features. Submission
failures retry next frame; allocation failures retry after a profile/settings
transition or dimension change. Missing cameras do not reuse stale AO.

Diagnostics report the effective settings, availability/reason, full/raw
dimensions, slice/step counts and estimated target bytes. The estimate includes
four bytes per pixel for hardware depth; actual backend allocation can differ.
`available` becomes true after the current frame's AO passes have been queued.

This is spatial, single-layer screen-space AO: off-screen and hidden geometry
cannot occlude, thin surfaces may halo, and camera motion can reveal sampling
noise. It does not use temporal history, motion vectors, depth mip chains or
bent normals. Depth-derived normals omit normal-map detail. Custom skinning,
instancing or deformation needs matching color and depth vertex programs;
the bundled materials currently use the non-skinned glTF vertex path.
