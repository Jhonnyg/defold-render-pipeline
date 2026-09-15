# Defold Render Pipeline

Defold Render Pipeline (DRP) is an early-stage configurable rendering-pipeline
extension for Defold. Its intended scope includes Forward+ clustered lighting,
PBR materials, shadows, HDR, ambient occlusion, depth of field, and rendering
diagnostics.

The current milestone implements the configuration foundation, native
storage-buffer bridge, Forward+ light assignment, and asset-pbr-based clustered
shading for opaque, alpha-masked, and transparent models. The cluster grid and
per-cluster light lists are extension-owned SSBOs. Punctual light data remains
in Defold's engine-owned `LightBuffer` UBO and is consumed directly by both the
assignment compute shader and clustered PBR materials.

## Current API

```lua
local drp = require("drp.drp")

local state, err = drp.initialize({
    quality = "balanced",
})

assert(state, err)

-- Requests are validated immediately and activated by begin_frame().
local request, request_err = drp.set_quality("high")
assert(request, request_err)

local transition = drp.begin_frame(1 / 60)
print(drp.get_requested_quality())
print(drp.get_effective_quality())
```

The bundled `/drp/drp.render` calls `drp.begin_frame()` at the start of each
frame. Applications should normally not call it themselves when using that
render script.

## Built-in profiles

- `compatibility`: portable conventional-forward baseline.
- `balanced`: default Forward+ target.
- `high`: higher light, shadow, and post-processing budgets.
- `ultra`: experimental maximum-quality target.

The `balanced`, `high`, and `ultra` profiles activate clustered lighting. The
`compatibility` profile renders conventional `model` materials without compute
or storage-buffer requirements. Cluster-authored predicates are replaced at
draw time with conventional asset-pbr variants, so the same scene can be used
by both paths. Other profile settings still describe future rendering intent.

Read [the quality-profile documentation](docs/QUALITY_PROFILES.md) and
[public API reference](docs/API.md) for details. Native bridge requirements and
its internal Lua surface are documented in
[the native bridge reference](docs/NATIVE_BRIDGE.md).

> **TODO — native glTF surface modes:** Automatic opaque, alpha-mask, and
> transparent classification should ultimately be provided by Defold's import,
> material, and default PBR systems rather than implemented independently by
> DRP. The proposed engine/extension boundary is recorded in
> [Native glTF PBR Surface Modes](docs/GLTF_PBR_SURFACE_MODES.md). Until then,
> DRP model material slots use explicit clustered surface variants.

The runnable [Sponza clustered-shading example](examples/README.md) is the
default bootstrap collection. Smaller cluster-assignment and quality API
examples remain available for focused testing.

## Project configuration

```ini
[bootstrap]
render = /drp/drp.renderc

[light]
max_count = 64

[shader]
exclude_gles_sm100 = 1

[drp]
default_profile = balanced
fallback_profile = compatibility
strict_capabilities = 0
```

With strict capabilities disabled, an unknown capability does not reject a
profile. An explicitly unsupported capability still causes fallback. Strict
mode treats both unknown and unsupported requirements as unavailable.

## Status

The configuration contracts, native SSBO bridge, clustered assignment,
asset-pbr-based clustered shading, transparent ordering, and runtime
compatibility overrides are active. Automatically assigning a clustered
material from imported material metadata still needs an editor/build-pipeline
integration. Shadows, HDR, and post-processing remain future work. See
[clustered lighting](docs/CLUSTERED_LIGHTING.md) for the current pass and
resource contract. The feature is functionally complete for its current MVP1
scope; its remaining validation and pre-PR work is tracked in the
[clustered feature README](drp/features/clustered/README.md).

---
