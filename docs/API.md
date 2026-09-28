# DRP Lua API

The public entry point is:

```lua
local drp = require("drp.drp")
```

## Lifecycle

### `drp.initialize(options)`

Initializes the singleton pipeline state. Repeated calls are idempotent and
return the current state.

Supported options:

| Field | Type | Purpose |
| --- | --- | --- |
| `quality` | string | Initial requested profile. |
| `platform` | string | Overrides platform detection. Useful in tests. |
| `capabilities` | table | Capability fields applied over native detection, primarily for tests or application-enforced limits. |
| `strict_capabilities` | boolean | Treat unknown required capabilities as unsupported. |
| `overrides` | table | Runtime settings merged onto the resolved profile. |

Returns a state table, or `nil, error`.

### `drp.begin_frame(dt)`

Commits a pending profile transition at the start of a frame. Returns a
transition table if a change was activated, otherwise `nil`.

The bundled render script calls this automatically. Deferring activation keeps
future render-target and GPU-buffer reallocations away from mid-frame state.

### `drp.finalize()`

Call from a render-script callback for explicit runtime teardown. Defold render
scripts have no `final()` callback. Engine/native-extension teardown handles
application exit.

Clears pipeline state, resource declarations, and listeners.

### `drp.reload()`

Re-resolves the requested profile and queues it for the next frame. This is the
initial hot-reload hook.

## Quality profiles

### `drp.set_quality(name)`

Validates and resolves the requested profile immediately, then queues it for
activation by `begin_frame()`. Returns the resolved request, or `nil, error`.

### `drp.get_requested_quality()`

Returns the latest requested profile name, including a pending request.

### `drp.get_effective_quality()`

Returns the currently active profile after capability fallback.

### `drp.get_active_profile()`

Returns a defensive copy of the active resolved profile.

### `drp.get_profile(name)` and `drp.get_profile_names()`

Inspect registered profile definitions. Returned tables are defensive copies.

### `drp.register_profile(name, profile)`

Registers or replaces a profile. The definition supports:

```lua
{
    name = "custom",
    description = "Project-specific profile",
    extends = "balanced",
    fallback = "compatibility",
    requirements = { "compute_shaders" },
    settings = {},
    platform_overrides = {},
}
```

Profile names must start with a lowercase letter and contain only lowercase
letters, numbers, underscores, or hyphens.

### `drp.unregister_profile(name)`

Removes a profile. Built-in profiles can technically be removed, but
applications should normally leave them registered.

## Runtime settings

### `drp.set_runtime_overrides(overrides)`

Replaces the complete runtime override table and queues a re-resolution of the
active request. Overrides are merged recursively onto profile settings.

### `drp.clear_runtime_overrides()`

Clears all runtime settings overrides.

Runtime overrides are intentionally profile-independent. Camera overrides will
be a separate layer when camera integration is added.

## Capabilities

### `drp.get_capabilities()`

Returns a defensive copy of the current capability record.

### `drp.set_capabilities(overrides)`

Re-detects capabilities using the supplied overrides and queues the current
quality request for re-resolution.

Capability values use three states:

| Value | Meaning |
| --- | --- |
| `true` | Confirmed supported. |
| `false` | Confirmed unsupported. |
| `nil` | Unknown to the current provider. |

When the native bridge is loaded, it reports the active adapter, compute and
storage-buffer support, related graphics features, and device limits. Explicit
values passed to `initialize()` or `set_capabilities()` take precedence. Fields
that the public engine API cannot query yet, such as float render-target support,
remain `nil`. Forward+ resolution also checks storage binding counts,
compute workgroup dimensions and invocations, shared memory, and the LightBuffer
uniform range. Insufficient values trigger profile fallback; unknown required
limits trigger fallback in strict mode. Compatibility exports report
`features.clustered_resources = false`, which runtime capability overrides
cannot enable again. See [compatibility builds](COMPATIBILITY.md).

The low-level storage-buffer bridge is internal infrastructure for DRP feature
modules rather than part of the stable application-facing facade. See
[`NATIVE_BRIDGE.md`](NATIVE_BRIDGE.md) for its contract.

## Notifications

### `drp.on_quality_changed(callback)`

Registers a callback invoked after a pending profile becomes active. Returns a
numeric listener handle.

The callback receives:

```lua
{
    frame = 42,
    dt = 0.016,
    previous = resolved_profile_request,
    current = resolved_profile_request,
}
```

### `drp.remove_quality_listener(handle)`

Removes a previously registered callback.

## State inspection

### `drp.get_state()`

Returns a defensive snapshot containing initialization state, frame number,
requested quality, effective quality, pending request, active profile, and
capabilities.

### `drp.get_feature_diagnostics(name)`

Returns a defensive snapshot of CPU-visible diagnostics for a feature. The
currently supported name is `"clustered"`. Its record contains the grid,
effective capacities, per-buffer byte sizes, total storage use, whether device
limits clamped the profile, and a conservative maximum assignment workload.

```lua
local cluster = drp.get_feature_diagnostics("clustered")
print(cluster.cluster_count, cluster.storage_bytes)
```

Exact occupancy, dropped-light, and overflowing-cluster counters are produced
on the GPU. Until Defold exposes asynchronous storage-buffer readback, inspect
those values through `lighting.cluster_debug`; magenta identifies overflow.

## HDR rendering

Add `/drp/features/hdr/hdr.go` once to the loaded scene; the Sponza and
clustered-renderer examples already include it. `balanced`, `high`, and `ultra`
enable HDR. The compatibility profile defaults to direct LDR output.

```lua
assert(drp.set_runtime_overrides({
    rendering = { hdr = true, hdr_exposure = 1.0 },
}))
local hdr = drp.get_feature_diagnostics("hdr")
```

`hdr_exposure` is manual EV, defaults to 0, and is clamped to [-16, 16]. Changes
activate at frame boundaries. `hdr = false` restores direct LDR output.
Diagnostics report `enabled`, `available`, `reason`, `width`, `height`,
`exposure`, `tone_mapper`, `color_format`, `color_bytes`, and `presenter_loaded`.
`color_bytes` excludes the backend-dependent depth attachment. Missing presenter
geometry or unsupported targets disable HDR while retaining scene rendering.
See [HDR](../drp/features/hdr/README.md) for material and custom-render integration.
