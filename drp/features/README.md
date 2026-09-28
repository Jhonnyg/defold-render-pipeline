# Render Features

Render features are internal DRP modules listed explicitly in
`drp/features.lua`:

```lua
local feature_modules = {
    require("drp.features.clustered.clustered"),
    require("drp.features.shadows.shadows"),
}
```

Each module may implement any of these hooks:

```lua
local M = {}

function M.initialize(context) end
function M.on_profile_changed(context, transition) end
function M.resize(context, width, height) end
function M.begin_frame(context) end
function M.render(context) end
function M.on_message(context, message_id, message, sender) end
function M.finalize(context) end

return M
```

Hooks run in list order. Finalization runs in reverse order so consumers are
torn down before their dependencies. Missing hooks are skipped, and errors
propagate normally with their original stack traces.

All hooks in a frame share one internal context containing the frame number,
delta time, active quality resolution and profile, capabilities, viewport, and
current profile transition when applicable. Features must treat the context and
its nested values as read-only.

This is intentionally a small internal convention rather than a public feature
framework. There is no runtime registration, hook validation, protected-call
wrapper, or special hook return protocol. Applications use the stable `drp.drp`
facade and quality settings instead of manipulating the feature list.

`clustered/clustered.lua` is the first implementation. It activates for
profiles whose `rendering.path` is `forward_plus`, owns the cluster SSBOs,
rebuilds view-space bounds only when their inputs change, assigns engine lights
every frame, and submits asset-pbr opaque, mask, transparent, and diagnostic
passes. See `clustered/README.md` for milestone status and
`docs/CLUSTERED_LIGHTING.md` for its resource contract.

`hdr/hdr.lua` owns the optional full-resolution floating-point scene target and
the final tone-mapping pass. Clustered shading runs first and uses the HDR
feature's target/output contract; HDR presents afterward. Presenter registration
messages are forwarded by the bundled render script through the same ordered
feature dispatcher. See [HDR](hdr/README.md) for setup and fallback behavior.
