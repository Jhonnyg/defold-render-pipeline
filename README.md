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

## Library packaging

The reusable library lives in `drp/`. Its `ext.manifest` and `src/` directory
provide the native extension alongside the Lua modules, render resources,
materials, shaders, and features. The repository's `game.project` exports this
single directory. The top-level files are the public Lua API (`drp.lua`), the
render script, the clustered and compatibility `.render` entry points, and the
extension manifest. Supporting Lua modules live in `drp/internal/`; applications
continue to use `require("drp.drp")`.

The library export setting is:

```ini
[library]
include_dirs = drp
```

Examples, tests, and development tools stay outside the library. Existing
`require("drp.drp")` imports and `/drp/` resource paths also work when DRP is
loaded as a project dependency.

Consuming projects must also add the
[asset-pbr 0.1.0 dependency](https://github.com/defold/asset-pbr/archive/refs/tags/0.1.0.zip)
and apply the [project configuration](#project-configuration) below. Defold does
not inherit a library's dependencies or project settings. Vantage is only
needed for this repository's examples.

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

The `balanced`, `high`, and `ultra` profiles activate clustered lighting. On a
cluster-capable device, switching to `compatibility` uses conventional asset-pbr
material overrides for the same scene. These profiles also enable HDR scene
rendering and tone mapping automatically when using `/drp/drp.render`; no HDR
game object is required. Compatibility defaults to LDR. Shadow and other
post-processing settings still describe future rendering intent. See
[HDR setup and controls](drp/features/hdr/README.md).

Devices without compute/SSBO support need a **compatibility build**: Defold loads
render and model shader resources before the Lua quality fallback can run.
Generate a separate source tree that preserves scene and material paths:

```sh
python3 tools/prepare_compatibility.py --output /tmp/drp-compatibility
```

Build that directory with Bob or open it in Defold. The exporter selects a
render resource without compute programs, replaces the three public clustered
materials with conventional shaders, and locks the build to compatibility.
The original project is unchanged. See [compatibility builds](docs/COMPATIBILITY.md).

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

With strict capabilities disabled, an unknown capability or limit does not
reject a profile. Explicitly unsupported features and insufficient binding,
workgroup, shared-memory, or uniform-buffer limits cause fallback. Strict mode
also rejects unknown required limits. Runtime settings are applied before
validating these requirements.

## Status

The configuration contracts, native SSBO bridge, clustered assignment,
asset-pbr-based clustered shading, transparent ordering, and runtime
compatibility overrides are active. Automatically assigning a clustered
material from imported material metadata still needs an editor/build-pipeline
integration. HDR scene rendering, manual exposure, and ACES-style tone mapping
are implemented as a separate feature. Shadows and the remaining post effects
remain future work. See
[clustered lighting](docs/CLUSTERED_LIGHTING.md) for the current pass and
resource contract. The feature is functionally complete for its current MVP1
scope; its remaining validation and pre-PR work is tracked in the
[clustered feature README](drp/features/clustered/README.md). Regression checks
and their commands are documented in [tests/README.md](tests/README.md).

## Future improvements / work

- **Shared scene/project shader data:** Provide a common shader include and a
  shared uniform buffer for values such as exposure, fog, global tint, and
  future shadow settings. Populate it from effective profile settings and
  accumulated runtime overrides after capability checks, so shaders receive
  the actual rendering state for that frame. Keep camera and per-pass data
  separate. Automatic binding for any shader declaring the block, similar to
  `LightBuffer`, would benefit from generic named global uniform-buffer support
  in Defold. DRP could initially supply the same data through render constants
  on each draw or compute dispatch. This is planned work, not an existing API.

---
