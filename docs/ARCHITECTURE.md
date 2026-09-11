# Foundation Architecture

This milestone establishes configuration boundaries without implementing any
rendering feature.

| Module | Responsibility |
| --- | --- |
| `drp.drp` | Stable public facade. |
| `drp.pipeline` | Singleton lifecycle, frame-boundary transitions, runtime overrides, and notifications. |
| `drp.quality` | Profile registry, inheritance, validation, platform overrides, and capability fallback. |
| `drp.capabilities` | Platform detection and the contract for future native GPU capability data. |
| `drp.resources` | Declaration-only resource ownership registry. It does not allocate GPU resources yet. |
| `drp.utils` | Internal shared helpers for defensive copying, table merging, array detection, and string joining. |
| `drp.profiles.*` | Built-in rendering-intent profiles. |

The bundled render script currently initializes the pipeline and commits quality
changes at frame boundaries. It deliberately contains no drawing or advanced
render feature passes.

The reserved `extension-dinline` directory will later host the native bridge for
generic engine APIs such as storage buffers, reflected named-buffer binding, and
light snapshots. No native source is included in this milestone. The directory
is listed in `.defignore` so an ordinary project build does not invoke the native
extension build service for an empty placeholder. Remove that ignore entry when
the native bridge implementation starts.

Feature directories are placeholders. Each future feature should declare its
required inputs, produced outputs, lifecycle, quality settings, capability
requirements, and debug views before implementation.
