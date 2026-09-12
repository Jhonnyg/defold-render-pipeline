# Foundation Architecture

This milestone establishes configuration boundaries and the native GPU-resource
bridge without implementing any rendering feature.

| Module | Responsibility |
| --- | --- |
| `drp.drp` | Stable public facade. |
| `drp.pipeline` | Singleton lifecycle, frame-boundary transitions, runtime overrides, and notifications. |
| `drp.quality` | Profile registry, inheritance, validation, platform overrides, and capability fallback. |
| `drp.capabilities` | Platform detection and the contract for future native GPU capability data. |
| `drp.native` | Internal Lua wrapper around optional native GPU operations. |
| `drp.resources` | Declaration-only resource ownership registry. It does not allocate GPU resources yet. |
| `drp.utils` | Internal shared helpers for defensive copying, table merging, array detection, and string joining. |
| `drp.profiles.*` | Built-in rendering-intent profiles. |

The bundled render script currently initializes the pipeline and commits quality
changes at frame boundaries. It deliberately contains no drawing or advanced
render feature passes.

The `extension-dinline` directory contains the active native bridge. It reports
graphics features and limits and owns validated storage-buffer handles. The Lua
layer never sees raw engine pointers. All buffers are deleted by explicit feature
cleanup, `drp.finalize()`, or native-extension shutdown.

Storage-buffer mutation and binding touch the installed graphics context and are
therefore restricted to the render script. Feature modules own binding order and
must bind immediately before the draw or compute dispatch that consumes a
buffer. The bridge intentionally contains no cluster names, layouts, or policy.

Future generic APIs such as reflected named-buffer registration and read-only
light snapshots can extend this boundary without moving clustered-lighting or
shadow policy into the engine.

Feature directories are placeholders. Each future feature should declare its
required inputs, produced outputs, lifecycle, quality settings, capability
requirements, and debug views before implementation.
