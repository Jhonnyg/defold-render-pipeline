# HDR and tone mapping

This feature ports the HDR portion of `defold-clustered-rendering-2` into DRP's
feature lifecycle. Opaque, alpha-masked, and transparent PBR surfaces render to
a full-resolution RGBA16F color target with hardware depth. Transparency blends
in linear space. A fullscreen pass applies manual exposure (`2^EV`), the POC's
ACES-style fitted curve, and the piecewise sRGB transfer function once.

This is HDR scene rendering with SDR presentation, not HDR10 display output.
Shadows, bloom, automatic exposure, color grading, and depth of field are not
part of this feature. The POC's DoF samplers and composite code are omitted.

## Setup

Use `/drp/drp.render` and add one `/drp/features/hdr/hdr.go` instance to a
collection that stays loaded while the scene renders. The clustered-cube and
Sponza examples already include it. This supplies the mesh required by
`render.draw()`; its script registers its lifetime with the renderer. Without
it, DRP renders directly in LDR rather than leaving an undisplayed HDR target.

If using a custom render script, forward its `on_message` calls to
`drp.pipeline.on_message(message_id, message, sender)` as the bundled script does.

`balanced`, `high`, and `ultra` enable HDR. `compatibility` defaults to LDR but
can opt into HDR on devices that support it. Settings also work through custom
profiles or the existing runtime override API:

```lua
local drp = require("drp.drp")
assert(drp.set_runtime_overrides({
    rendering = {
        hdr = true,
        hdr_exposure = 1.0, -- +1 stop doubles scene intensity before tone mapping
    },
}))
```

Changes activate at the next frame boundary. Exposure defaults to 0 EV and is
clamped to [-16, 16]; invalid/non-finite values use 0. Exposure-only changes do
not reallocate targets. Setting `hdr = false` restores the original material
output conversion and releases the HDR target. Runtime overrides replace the
previous override table, so include any other overrides you want to retain.

## Integration and fallback

- The HDR module owns target allocation, presentation, and cleanup. Clustered
  rendering selects its scene target and passes `drp_output_settings` to the
  materials. The feature dispatcher presents after scene rendering.
- All six DRP PBR surface shaders support both linear HDR and direct LDR output.
  Editor previews retain the existing display conversion. While HDR is active,
  the conventional opaque `model` predicate uses DRP's forward PBR override so
  asset-pbr materials do not apply an early display conversion. Custom shaders
  using that predicate must follow this PBR contract; custom effects need their
  own HDR-aware draw integration.
- Clear-color RGB values are linear scene values when HDR is active.
- The occupancy heatmap bypasses HDR and exposure so diagnostic colors remain
  unchanged. Frames without an active camera do not present stale scene color.
- Viewport changes recreate the target. Finalization, profile changes, presenter
  removal, and capability loss release it. Render scale is not implemented here;
  the target and cluster grid both use the window's physical pixel dimensions.
- Explicit `features.float_render_targets = false`, missing RGBA16F texture
  support, exceeded target-size limits, or failed allocation retain direct LDR
  rendering without disabling clustered lighting. In strict capability mode,
  unknown float-render-target support also disables HDR. In non-strict mode,
  allocation is attempted when support is unknown. Allocation failures retry
  on a profile reload/change or viewport change rather than every frame.
- The compatibility export includes only portable HDR shaders and defaults to
  HDR off; enabling HDR there does not introduce compute or SSBO dependencies.

Defold render scripts do not support a `final()` callback. Runtime pipeline
teardown must call `drp.finalize()` from a valid render-script callback; normal
application exit uses engine/native-extension teardown.

`drp.get_feature_diagnostics("hdr")` reports requested/enabled state, actual
availability, fallback reason, dimensions, exposure, presenter presence, and
color allocation bytes (8 bytes/pixel, excluding backend-specific depth memory).

## Validation

`tests/hdr_spec.lua` checks target lifetime, resize/toggles, exposure, strict and
non-strict fallback, failed-allocation recovery, missing presenters, stale-frame
avoidance, and correct texture unbinding. `tests/hdr_math_spec.cpp` compiles the
production GLSL math and checks exposure, highlight preservation, finite output,
monotonicity, and the sRGB boundary. The clustered integration test verifies
that HDR scene draws receive linear-output constants before the final resolve.

GPU smoke checks: run the cube or Sponza example, compare HDR off/on and EV
-2/0/+2, toggle the heatmap, switch quality, resize, and move the camera. Check
cutout coverage and transparent objects over bright backgrounds. The initial
port was exercised on the Metal SSBO engine; other backends still need live QA.
