# Render features

Render features are Lua modules selected in render-script initialization through
`pipeline.initialize({ features = { ... } })`. The default preset includes GTAO,
clustered lighting, and HDR. The compatibility preset includes GTAO and HDR.
Features contribute to the [shared scene stages](../internal/README.md); the
pipeline owns their ordering and the scene renderer owns scene draws.

Each module may implement these hooks:

```lua
local M = { name = "example" }

function M.initialize(context) end
function M.on_profile_changed(context, transition) end
function M.resize(context, width, height) end
function M.begin_frame(context) end
function M.render_before_scene(context) end
function M.configure_scene(context, pass) end
function M.prepare_scene(context, pass) end
function M.render_after_scene(context, pass) end
function M.on_message(context, message_id, message, sender) end
function M.get_diagnostics() return {} end
function M.get_debug_views() return {} end
function M.get_properties() return {} end
function M.get_debug_source(context, id) end
function M.finalize(context) end

return M
```

Hooks run in list order, with finalization in reverse order. Missing hooks are
skipped; errors propagate with their original stack traces. All native fullscreen
submissions happen during `begin_frame`, before any draw builds the render list.

The frame context contains the frame number, delta time, active quality/profile,
capabilities, viewport, and any profile transition. Camera and debug selection
are snapshotted before `begin_frame`. Features treat the context as read-only;
they contribute to a separate mutable scene pass during configuration and
preparation. Applications use quality settings for runtime changes. Projects select feature
modules at startup without modifying DRP internals; composition stays fixed until
finalization. A disabled included feature remains visible in the debug UI, while
an excluded feature has no hooks, properties, diagnostics, or debug views.

[GTAO](gtao/README.md) produces linear scene depth and filtered visibility before
the shaded scene. It contributes its visibility texture and constants to scene
shading and exposes filtered AO, raw AO, and depth as debug sources.

[Clustered lighting](clustered/README.md) activates for the `forward_plus` path.
It owns cluster SSBOs, builds view-space bounds, assigns engine lights, and
contributes constants/storage bindings. Its occupancy visualization uses the
same shared scene draws.

[HDR](hdr/README.md) contributes a floating-point scene target and requests
linear output, then tone maps the completed scene. Its native fullscreen
geometry requires no scene helper.

The [shared debug controller](../internal/README.md#feature-debug-views) queries
feature-owned view descriptors and current-frame sources. Texture views draw
after HDR; scene views request a generic post-processing bypass. The optional
[debug overlay](../debug/README.md) supplies UI, keybindings, and controls from
feature-owned `get_properties()` schemas. Controls edit specific runtime
override paths; they do not replace entire settings groups. Features retain
ownership of their resources and do not need to import one another.

## Selecting features in a project

Copy `/drp/drp.render` and `/drp/drp.render_script` into your project and point the
copied render resource at the copied script. In that script's `init`, use an
explicit list, in render-stage order:

```lua
local pipeline = require("drp.internal.pipeline")
local project_features = {
    require("drp.features.gtao.gtao"),
    require("drp.features.hdr.hdr"),
    -- require("my_project.features.fog"),
}

function init(self)
    local state, err = pipeline.initialize({ features = project_features })
    assert(state, err)
end
```

Keep the copied script's `update`, `on_message`, and `on_reload` callbacks and set
`bootstrap.render` to your copied renderer. Configure this in the render script,
before initialization; a later game-script call cannot change the running
registry, and game/render Lua contexts may be separate. `features = {}` selects
only the shared scene renderer. Omitting `features` uses the built-in default,
or the compatibility preset when `drp.clustered_resources = 0`.

`drp.features.presets` also provides `default()` and `compatibility()` lists for
projects that want to extend a built-in set. Keep literal `require()` calls for
custom modules so Bob includes their Lua dependencies. Included features execute
in list order within each stage; finalization runs in reverse order.

### Render resources and packaging

Feature selection controls execution and inspection. It does not automatically
add or remove compiled resources. Start from the bundled `.render` resource,
retain shared scene/debug resources and each selected feature's materials/compute
programs, and add resource declarations for custom features. Both bundled render
resources already contain their presets' dependencies. The compatibility export
tool sets the compatibility preset's build flag as well as replacing the renderer.

Profiles can retain settings for excluded features; those settings do not include
a module or cause it to execute. Keep the selected profile consistent with your
pipeline (for example, use a forward profile when omitting clustered lighting).
Removing Lua hooks alone does not strip shaders referenced by `.render` or model
materials from a build. Automatic resource generation is outside this API.

## Feature property schema

A feature declares its name and optional display label, capability requirements,
and `get_properties()` array. IDs are local to the feature; the registry prefixes
them with the feature name. UI and other property consumers use the same schema:

```lua
local M = { name = "fog", label = "Fog" }

function M.get_properties()
    return {
        {
            id = "density",
            path = "post.fog_density",
            type = "number",
            default = 0.25,
            limits = { min = 0, max = 100 },
            ui = { label = "Density", min = 0, max = 1, step = 0.01 },
            diagnostic_key = "density",
        },
    }
end

-- Rendering hooks read context.profile.settings.post.fog_density.
return M
```

This creates property `fog.density` and its slider without any UI changes.
Defaults fill absent settings beneath profiles, platform overrides, and runtime
overrides. Feature configuration still owns effective device-dependent limits
and normalization of raw runtime overrides.

| Field | Meaning |
| --- | --- |
| `id` | Local identifier, unique within the feature. |
| `path` | Owned dotted settings path; duplicate or overlapping paths are rejected. |
| `type` | `boolean`, `number`, or `enum`. |
| `default` | Required value of the property's type. |
| `limits` | Optional numeric `min`/`max`; property edits clamp to these limits. |
| `integer` | Round numeric edits to the nearest integer. |
| `options` | Ordered, unique string values for enums. |
| `on_value`, `off_value` | Optional distinct strings mapping a boolean to a setting such as a render path. |
| `ui` | Presentation hints; `false` excludes the property from the debug UI. Numbers require finite `min`/`max`. |
| `ui.label`, `ui.step`, `ui.scale` | Display label, slider increments, and `linear` or `log` scaling. |
| `diagnostic_key` | Optional field in `get_diagnostics()` containing the effective value. |

The registry validates the complete composition before initialization and keeps
private copies of descriptors. UI sliders constrain interactive edits to their
editing range, independently of numeric domain limits. Existing configured
values outside slider bounds remain visible. Reset removes only the exposed
property overrides for the selected control/feature, preserving other settings.

A feature may declare `requirements = { "float_render_targets" }` (capability
names from `context.capabilities.features`). Unsupported features remain listed
with an explanation and disabled editing; reset remains available. Features
that are merely disabled by settings remain editable so they can be enabled.
Features without diagnostics are still editable. Diagnostics describe current
render availability separately from capability support.

Debug views remain feature-owned `get_debug_views()` and `get_debug_source()`
hooks. View IDs are already namespaced, for example `fog.density`; only included
features contribute views. The existing `none` view is always present.
