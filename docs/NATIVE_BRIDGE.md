# Native Bridge

The DRP native bridge is active and registered as the global Lua module
`drp_native`. DRP feature code should use the `drp.native` wrapper instead of
calling that global directly.

This is an internal pipeline API. Applications should continue to use
`require("drp.drp")` as the stable public facade.

## Engine requirement

The bridge requires a Defold SDK that provides the generic storage-buffer and
graphics capability APIs introduced on the SSBO-support engine branch:

- `dmGraphics::NewStorageBuffer()` and deletion/update operations;
- `dmGraphics::EnableStorageBuffer()` and `DisableStorageBuffer()`;
- `dmGraphics::IsContextFeatureSupported()`; and
- `dmGraphics::GetGraphicsContextLimits()`.

An older stock SDK will fail to compile this native extension. This is expected
until those engine APIs are available in the Defold release used by the project.

## Capability discovery

`drp.capabilities.detect()` automatically merges native data over its portable
Lua baseline. Callers can still supply explicit overrides, which are applied
last. The native provider reports:

- adapter family;
- compute shaders, storage buffers, texture arrays, 3D textures, instancing,
  multiple render targets, and min/max blend equations; and
- uniform/storage ranges, texture/framebuffer limits, per-stage resource limits,
  vertex limits, and compute workgroup limits.

Features that do not yet have a public engine query remain unknown (`nil`) in
the capability record rather than being guessed.

## Storage-buffer contract

```lua
local native = require("drp.native")

local buffer = native.create_storage_buffer(
    4096,
    native.BUFFER_USAGE_DYNAMIC_DRAW
)

native.update_storage_buffer(buffer, 0, binary_data)
native.bind_storage_buffer(buffer, 0, 3)
-- Dispatch compute work or draw here.
native.unbind_storage_buffer(buffer)
native.delete_storage_buffer(buffer)
```

The complete internal API is:

| Function | Purpose |
| --- | --- |
| `is_available()` | Reports whether the native module loaded. |
| `get_capabilities()` | Returns native features, limits, and adapter data. |
| `create_storage_buffer(size, usage, data)` | Creates a buffer and returns a validated numeric handle. |
| `resize_storage_buffer(handle, size, usage, data)` | Replaces the complete allocation. |
| `update_storage_buffer(handle, offset, data)` | Uploads an aligned binary-string range. |
| `get_storage_buffer_size(handle)` | Returns the logical byte size. |
| `bind_storage_buffer(handle, set, binding)` | Binds for the next matching draw or dispatch. |
| `unbind_storage_buffer(handle)` | Removes all current bindings of that buffer. |
| `delete_storage_buffer(handle)` | Deletes one allocation and invalidates its handle. |
| `reset()` | Deletes every allocation owned by the bridge. |

Sizes, update offsets, and update lengths must be four-byte aligned. Initial or
replacement data must exactly match the allocation size. Binary data is passed
as a Lua string, so embedded zero bytes are supported.

## Thread and lifetime rules

All storage-buffer functions must be called from the render script. They operate
on the installed graphics context and are not game-object script APIs.

Feature modules should delete their buffers during their own finalization.
`drp.finalize()` calls `reset()` as a safety net, and native-extension shutdown
does the same. Numeric handles are bridge-owned IDs rather than raw pointers;
using a deleted or unknown handle raises a Lua error.

## Deliberate omissions

The bridge currently does not expose cluster layouts, light selection, shadow
policy, raw native handles, or arbitrary pointer uploads. Reflected named-buffer
registration and engine-light snapshots remain separate future integrations.
