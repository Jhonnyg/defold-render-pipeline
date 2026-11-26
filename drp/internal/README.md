# Scene rendering and feature stages

`pipeline.lua` schedules feature work around the shared scene renderer in
`scene.lua`. Feature modules own their GPU resources and preparation passes;
they do not import one another or own the complete scene draw sequence.

The clustered feature supplies depth ranges, light assignment, shader constants
and buffer bindings. HDR supplies a scene target and linear-output requirement,
then presents the completed scene. `scene.lua` owns camera/viewport setup,
clearing, material selection, shared bindings and the opaque, masked, model and
transparent draws for both lighting paths.

## Frame stages

1. Apply pending profile changes and resize notifications. After quality
   listeners run, snapshot the last enabled camera into `context.camera`.
2. Snapshot the selected debug view into `context.debug`, then call every
   feature's `begin_frame(context)`. Allocate resources and submit
   all native fullscreen entries here, before any draw builds the render list.
3. Call `render_before_scene(context)` for passes that produce scene inputs
   using their own targets.
4. Create a fresh scene pass. If there is no render runtime or enabled camera,
   skip scene configuration, preparation, shading and presentation.
5. Call `configure_scene(context, pass)` to contribute the output target,
   encoding requirement, constants and named textures.
6. Begin the scene: select its target/camera/viewport, restore write masks and
   clear color/depth/stencil. `drp_output_settings` is derived from the pass's
   `linear_output` flag.
7. Call `prepare_scene(context, pass)`. Clustered lighting records depth ranges
   and assigns lights against this freshly cleared target. Preparation hooks
   must preserve the target, camera and viewport, and reset any compute program
   before returning. Generic code cannot even disable compute on unsupported
   backends, so this cleanup remains with the feature that enabled it.
8. Draw the scene using its constants and bindings. Restore depth writes for
   opaque/masked geometry, then disable them and blend transparent geometry
   back-to-front. Unbind named textures and mark the pass `rendered`.
9. Call `render_after_scene(context, pass)`. HDR presents only if its target was
   selected and the scene was rendered, once per pass.
10. Query and present the selected debug source directly on the backbuffer,
    then draw the optional `drp_debug_overlay` GUI and reply to status requests.

Hooks are optional. Registration order in `features.lua` orders features within
each stage. The existing initialize, profile-change, resize, message and finalize
hooks remain; finalization runs features in reverse registration order.

## Per-scene data

The frame context is read-only to features. Camera data is available during
`begin_frame` and rendering; it is not promised during initialization, profile
changes or resize notifications. The pipeline creates a separate mutable pass
for configuration and preparation. Features may retain their own resources,
but must not reuse a previous pass's constants, bindings or completion state.

| Field | Default | Contribution |
| --- | --- | --- |
| `target` | Backbuffer | Output feature selects the scene render target. |
| `linear_output` | `false` | Requests linear shader output for later presentation. |
| `lighting_path` | `"forward"` | A ready lighting feature selects `"clustered"`. |
| `override_model_material` | `false` | Requests DRP's glTF override for the conventional opaque `model` predicate. Linear output also requires this override. |
| `constants` | New render constant buffer | Features write their named shader constants. Scene owns `drp_output_settings`. |
| `textures` | Empty array | Append `{ sampler, target, attachment }` for scene-wide named textures. |
| `storage_buffers` | Empty array | Append `{ handle, set, binding }` for scene-wide storage bindings. |
| `rendered` | `false` | Only the scene renderer marks completion; output features inspect it. |

There is one scene-output owner. Features use distinct constant/sampler names
and descriptor slots. A feature that is unavailable leaves the default target
or lighting path selected, omits its resource bindings and supplies neutral
constants when its shader interface requires them. Thus missing optional
features do not disable other rendering features.

The native SSBO API binds immediately, while Lua `render.draw` and compute
dispatches enqueue commands. Storage descriptors therefore remain stable and
bound through command execution; scene completion must not unbind them.
Reusing one descriptor slot for different buffers in queued passes would need
native command capture. Named texture bindings use queued render commands and
can safely be disabled after scene draws.

All of these modules and hooks are internal implementation details. Applications
continue to use `require("drp.drp")` and the bundled render script.

## Feature debug views

`debug.lua` coordinates selection and presentation without owning feature
resources. A feature can implement these optional hooks:

- `get_debug_views()` returns stable `{ id, label, description, kind }`
  descriptors. IDs are namespaced, for example `gtao.filtered`; `kind` is
  `texture` or `scene`. The registry attaches the feature name.
- `get_debug_source(context, id)` returns the current frame's source, or
  `nil, reason` when it was not produced. A texture source supplies
  `{ target, attachment, width, height, mode }`; mode is `visibility` or
  `depth` (also supplying the positive camera `far` plane). A scene source
  confirms completion of its visualization and may supply dimensions.

The controller borrows targets only after feature/scene rendering. It does not
cache handles, allocate copies, enable features, or alter quality overrides.
Features must reject previous-frame data after camera loss, disable, or failed
passes. Texture views are presented after HDR without tone mapping or gamma.
Scene visualizations use `context.debug.bypass_post` to request neutral post
processing; features need not know which other feature owns that view.

The optional GUI communicates with the render script via messages, so separate
Lua contexts work. Selection becomes active at the next frame boundary; status
replies are sent after rendering. The [debug README](../debug/README.md) documents
commands and reusable collection/input setup.

The same transport exposes the renderer's quality-profile registry through
`profiles` and queues tier changes through `set_quality`. This calls the existing
pipeline quality API, preserving runtime overrides, validation, capability
fallback and frame-boundary activation. Status reports requested, pending and
effective quality separately. The GUI shares a paged popup implementation between
quality and view selection; it never loads a GUI-local quality registry.

## Live feature controls

Features publish general `get_properties()` schemas; see the
[feature contract](../features/README.md#feature-property-schema).
`features.lua` validates and freezes the startup registry and `properties.lua`
compiles its property catalog. Defaults fill absent profile settings, and property
writes validate types and numeric domains independently of UI hints.

`debug_controls.lua` translates that catalog into flat GUI descriptors. It queries
the configured registry instead of capturing a catalog at module load. Messages
address exposed IDs, never arbitrary paths. Interactive edits clamp to slider
ranges; existing external values stay intact. Feature reset clears only its
exposed paths and resolves once, preserving unrelated settings and pending
quality requests. Capability support controls editability; current-frame
availability and effective values come from feature diagnostics.

The renderer streams view descriptors on a `views` request for the GUI selector,
and one control descriptor/value per message to stay below Defold's
message-size limit. Replies follow rendering, so feature availability and
effective values describe that frame. The overlay keeps its in-progress drag
value across polls and sends at most one pending value per control per update.
These edits last for the running session and do not save profile/project files.
