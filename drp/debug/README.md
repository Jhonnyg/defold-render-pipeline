# Render debug overlay

This optional collection provides the same debug controls in any scene using the
DRP renderer. Sponza and the clustered-renderer example already include it.

| Key | Action |
| --- | --- |
| F1 | Show or hide the panel; the selected view stays active. |
| F2 | Select the next debug view. |
| F3 | Select the previous debug view. |
| F4 | Return to normal rendering. |

On keyboards that reserve function keys for system controls, hold Fn while
pressing the key. Camera movement and mouse controls remain available.

Use filtered AO to see the final ambient-occlusion texture without lighting or
material textures. White means unoccluded; darker pixels mean more occlusion.
Raw AO exposes the unfiltered sampling result, while scene depth helps check the
geometry used to reconstruct AO. Depth is logarithmic: nearer surfaces are dark,
farther surfaces are bright, and the empty background is black. Inspect contact
points and wall-floor corners.
Use the **View** selector at the top of the panel to choose a specific view.
Its choices come from the renderer's configured features, including custom
features. The default list is Scene, AO, Raw AO, Scene depth, and Cluster
occupancy. Longer lists have page buttons. F2/F3/F4 remain available and keep the
selector synchronized. Click outside the list to dismiss it.

The panel reports the selected view, its availability, and texture dimensions.

## Live controls

Tabs are generated from the renderer's included features and their property
schemas. The default preset provides **AO**, **HDR**, and **Clustered**; a custom
pipeline shows its own set without editing this overlay. Select a tab to edit
that feature while the scene is running. Checkboxes enable features, sliders adjust numeric settings,
and clicking a choice selects its next option. AO exposes radius, intensity,
power, bias, quality, and resolution; HDR exposes exposure; clustered lighting
exposes tile size, depth slices, and lights per cluster.

**Clustered lighting** switches between Forward+ and the forward fallback.
Turning it off keeps scene lights enabled; the fallback shaders evaluate up to
eight lights. It is not a master light switch. The footer explains the fallback
when clustered lighting is disabled. Choose **Cluster occupancy** in the View
selector to inspect clusters without changing the rendering-path setting.

Changes become runtime overrides on the next rendered frame. A `*` marks a
setting with an override. **R** restores one setting from the current profile;
**Restore feature settings** restores only the controls in that feature. Other
overrides stay intact. These edits are temporary and do not write profile files.
F4 resets the debug view only, leaving these controls unchanged. Return to the
scene with F4 when adjusting exposure: AO and depth debug views intentionally
display their data without HDR tone mapping or exposure.

Included features disabled by settings remain editable. Features with unsupported
capability requirements have disabled editing and a reason; reset still works.
Excluded features contribute no controls or views.

The panel reports when a feature is unavailable or when its effective setting
differs from the requested value, for example because of a device limit.
External values outside a slider's editing range remain visible; only the thumb
is clamped. Dragging that slider chooses a value within its editing range.

The panel captures a mouse press made inside it until release, including when
the pointer moves outside. Camera movement keys and mouse drags started outside
the panel continue to work. Hide the panel with F1 for an unobstructed view.

Selecting a view does not turn on the feature or change its settings. An
unavailable view leaves the scene visible and reports the reason. Without
a scene camera, only the cleared background and panel are visible. F4 changes
only the debug view: existing quality profiles and runtime overrides remain in
effect, including a previously configured `lighting.cluster_debug` heatmap.

## Add it to another scene

1. Add `/drp/debug/debug.collection` as a collection instance in the scene.
2. Add these actions to the input binding selected in `game.project`:

   | Input | Action |
   | --- | --- |
   | F1 | `drp_debug_toggle` |
   | F2 | `drp_debug_next` |
   | F3 | `drp_debug_previous` |
   | F4 | `drp_debug_reset` |

   For mouse controls, bind the primary mouse button to `drp_debug_pointer`,
   or configure the overlay to use an existing action as shown below.
   Do not bind the same mouse button twice.

   Merge these with the project's existing bindings. This repository's
   `/input/game.input_binding` combines the actions with Vantage's camera
   controls; applications using different controls should keep their own map.

To reuse an existing input map, configure action names in `game.project`:

```ini
[drp_debug]
pointer = VANTAGE_MOUSE_1
pointer_secondary = VANTAGE_MOUSE_2
pointer_middle = VANTAGE_MOUSE_3
```

These are this project's camera action names, not dependencies of the overlay.
Without configuration, pointer actions default to `drp_debug_pointer`,
`drp_debug_pointer_secondary`, and `drp_debug_pointer_middle`. The optional
`toggle`, `next`, `previous`, and `reset` keys override the corresponding
`drp_debug_*` action names. Panel key hints describe the default F1–F4 bindings.

The renderer works without this collection. The collection supplies input and
status UI only; debug view selection and drawing belong to the renderer. Its
GUI and font materials use the `drp_debug_overlay` tag, drawn after the selected
view so that the panel stays visible.

## Messages

The overlay communicates through messages rather than sharing Lua module state
with the render script. Send `drp_debug_command` to `@render:` with a `command`
field of `status`, `views`, `next`, `previous`, `reset`, or `set`. Use `set` with a `view`
field to select a particular view:

```lua
msg.post("@render:", "drp_debug_command", {
    command = "set",
    view = "gtao.filtered",
})
```

| View ID | Result |
| --- | --- |
| `none` | Normal configured scene rendering. |
| `gtao.filtered` | Final, filtered AO visibility. |
| `gtao.raw` | AO visibility before filtering. |
| `gtao.depth` | Logarithmic scene depth used by AO. |
| `clustered.occupancy` | Cluster occupancy and overflow heatmap. |

The renderer replies to the sender with `drp_debug_status`, including the selected `view`, `label`,
`available`, `reason`, and `description`. Views can also report `width` and `height`.

The panel requests status, views, and controls on startup and every half-second
while visible. A `views` reply streams `drp_debug_views_begin` (`count`, `frame`),
one `drp_debug_view` per descriptor (`id`, `label`, `description`, `kind`, optional
`feature`), then `drp_debug_views_end` (`frame`). The GUI accepts only a complete
list with matching frame and unique IDs, and keeps the open list stable across
unchanged polls. Views from disabled included features remain selectable and
report why they are unavailable; excluded features contribute no choices. Each controls reply is a `drp_debug_controls_begin` message, one
`drp_debug_control` message per descriptor, then `drp_debug_controls_end`.
Descriptors carry IDs, feature names, labels, types, ranges or choices, current
values, override state, feature availability, and `editable`. The UI disables
editing when `editable == false`. The GUI does not contain
feature-specific settings paths.

Control commands use the same `drp_debug_command` message:

```lua
msg.post("@render:", "drp_debug_command", {
    command = "set_control", id = "gtao.intensity", value = 1.5,
})
msg.post("@render:", "drp_debug_command", {
    command = "reset_control", id = "gtao.intensity",
})
msg.post("@render:", "drp_debug_command", {
    command = "reset_feature", feature = "gtao",
})
```

A rejected edit returns `drp_debug_control_error` with a reason. Slider movement
is coalesced to one edit per control per frame; incoming polls do not move a
thumb while it is being dragged.
