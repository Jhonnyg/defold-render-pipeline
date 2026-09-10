# Defold Render Pipeline

Defold Render Pipeline (DRP) is an early-stage configurable rendering-pipeline
extension for Defold. Its intended scope includes Forward+ clustered lighting,
PBR materials, shadows, HDR, ambient occlusion, depth of field, and rendering
diagnostics.

The current milestone deliberately implements **configuration only**. It
contains the package structure, public Lua facade, pipeline lifecycle, quality
profiles, capability-based fallback, and resource declarations. It does not yet
render scene content or implement any advanced rendering feature.

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

Profiles describe future rendering intent. The settings do not activate
rendering features in this milestone.

Read [the quality-profile documentation](docs/QUALITY_PROFILES.md) and
[public API reference](docs/API.md) for details.

The runnable [quality API example](examples/README.md) demonstrates profile
registration, runtime overrides, quality requests, and transition callbacks.

## Project configuration

```ini
[bootstrap]
render = /drp/drp.renderc

[drp]
default_profile = balanced
fallback_profile = compatibility
strict_capabilities = 0
```

With strict capabilities disabled, an unknown capability does not reject a
profile. An explicitly unsupported capability still causes fallback. Strict
mode treats both unknown and unsupported requirements as unavailable.

## Status

The project is establishing stable configuration and lifecycle contracts before
porting code from the exploratory clustered renderer. See the design documents
in `docs/` for the intended architecture and next steps.

---
