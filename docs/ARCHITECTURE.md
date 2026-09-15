# Foundation Architecture

This milestone establishes configuration boundaries, the native GPU-resource
bridge, and an initial clustered-lighting feature.

| Module | Responsibility |
| --- | --- |
| `drp.drp` | Stable public facade. |
| `drp.pipeline` | Singleton lifecycle, frame-boundary transitions, runtime overrides, and notifications. |
| `drp.features` | Static ordered feature list and lightweight lifecycle dispatcher. |
| `drp.quality` | Profile registry, inheritance, validation, platform overrides, and capability fallback. |
| `drp.capabilities` | Platform detection and the contract for future native GPU capability data. |
| `drp.native` | Internal Lua wrapper around optional native GPU operations. |
| `drp.resources` | Resource-name, ownership, descriptor-set, and binding registry. Feature modules still allocate their own GPU resources. |
| `drp.features.clustered.clustered` | Persistent cluster-buffer lifecycle, dirty bounds rebuilding, compute assignment, clustered PBR submission, and assignment diagnostics. |
| `drp.utils` | Internal shared helpers for defensive copying, table merging, array detection, and string joining. |
| `drp.profiles.*` | Built-in rendering-intent profiles. |

The bundled render script initializes the pipeline, supplies the current
viewport, commits quality changes at frame boundaries, and asks the built-in
features to render. Render-pass implementation remains in each feature module.

Built-in features are listed explicitly in `drp/features.lua`. Their hooks run
in list order for initialization, profile changes, resize, frame setup, and
rendering; cleanup runs in reverse order. Hooks in a frame share one internal
context and must treat it as read-only. Errors propagate normally, without a
protected-call wrapper or feature-specific return protocol.

The `extension-dinline` directory contains the active native bridge. It reports
graphics features and limits and owns validated storage-buffer handles. The Lua
layer never sees raw engine pointers. All buffers are deleted by explicit feature
cleanup, `drp.finalize()`, or native-extension shutdown.

Storage-buffer mutation and binding touch the installed graphics context and are
therefore restricted to the render script. Feature modules own binding order and
must bind immediately before the draw or compute dispatch that consumes a
buffer. The bridge intentionally contains no cluster names, layouts, or policy.

The engine's built-in `LightBuffer` is deliberately not wrapped by the native
bridge. Defold owns, populates, and binds that UBO by reflected block name. DRP
only declares a matching read-only `std140` block in shaders. This avoids a CPU
copy and keeps light lifetime and component integration in the engine.

See [clustered lighting](CLUSTERED_LIGHTING.md) for the implemented pass order,
bindings, material tags, and current limitations. Other feature directories
remain placeholders.
