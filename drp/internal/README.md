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
2. Call every feature's `begin_frame(context)`. Allocate resources and submit
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
