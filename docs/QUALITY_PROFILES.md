# Quality Profiles

## Resolution order

DRP resolves configuration in this order:

```text
extension defaults
    -> selected profile inheritance
    -> platform override
    -> capability fallback
    -> runtime settings overrides
    -> camera overrides (future)
```

The requested profile expresses the application's intent. The effective profile
is what the current device can run.

## Inheritance

Profiles may derive from one parent through `extends`. Settings and platform
overrides are merged recursively. Requirements declared by a child replace the
inherited requirements list, while omitted requirements are inherited.

The built-in chain is:

```text
compatibility <- balanced <- high <- ultra
```

Inheritance cycles and missing parents are reported during resolution.

## Capability fallback

Profiles declare required feature names:

```lua
requirements = {
    "compute_shaders",
    "storage_buffers",
    "float_render_targets",
}
```

If a required capability is explicitly `false`, DRP follows the profile's
`fallback` field. In strict mode, an unknown (`nil`) capability also triggers
fallback.

Fallbacks continue until DRP finds a supported profile or reaches an error. The
resolution record retains human-readable reasons for every rejected profile.

## Platform overrides

Platform overrides are applied after inheritance and before capability checks:

```lua
platform_overrides = {
    html5 = {
        settings = {
            lighting = {
                max_lights_per_cluster = 48,
            },
        },
    },
}
```

Supported platform names are normalized to lowercase names such as `android`,
`html5`, `ios`, `linux`, `macos`, and `windows`.

## Activation

`drp.set_quality()` only queues an already validated resolution. The render
script commits it through `drp.begin_frame()`. This separation is required once
profile changes reallocate render targets, histories, atlases, and storage
buffers.

## Runtime overrides

Runtime overrides are merged onto the effective profile's `settings` table.
They do not mutate the registered profile and survive profile switches until
cleared.

For example:

```lua
drp.set_runtime_overrides({
    rendering = {
        render_scale = 0.85,
    },
})
```

## Adding a project profile

```lua
local drp = require("drp.drp")
local profile = require("main.render_profiles.cinematic")

local ok, err = drp.register_profile(profile.name, profile)
assert(ok, err)
```

Register custom profiles before requesting them. A future editor integration can
compile profile assets into the same runtime representation.
