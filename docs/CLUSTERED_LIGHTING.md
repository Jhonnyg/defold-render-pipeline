# Clustered Lighting

## Scope

The initial DRP Forward+ path partitions the camera frustum into screen-space
tiles and logarithmic depth slices. A compute pass intersects every active
engine light with the resulting view-space cluster bounds and writes compact
per-cluster lists. The default result is an assignment heatmap on clustered
geometry, so cluster lookup, occupancy, and overflow can be validated before
the clustered PBR result is treated as production-ready.

This iteration supports directional, point, and spot assignment. It does not
yet include shadows, image-based lighting, HDR output, post-processing,
light-list prioritization, or temporal reuse.

## LightBuffer ownership

Defold continues to own the light component storage and `LightBuffer` UBO. DRP
does not allocate a second light buffer and does not copy light records.

Both `cluster_assign.cp` and the clustered PBR fragment shader declare the
engine ABI by the reflected name `LightBuffer`:

```glsl
struct Light {
    vec4 position;
    vec4 color;
    vec4 direction_range;
    vec4 params;
};

layout(std140) uniform LightBuffer {
    vec4 light_info;
    Light lights[64];
};
```

The engine recognizes and binds that block for graphics and compute programs.
The shader always clamps the active count to its 64-light capacity. The bundled
project uses `[light] max_count = 64`; a larger engine allocation is valid, but
a smaller allocation cannot satisfy this shader declaration.

Because clustered fragment shaders contain SSBO declarations, projects using
these always-included render resources must also set
`[shader] exclude_gles_sm100 = 1`. GLES 1.00 cannot represent the resource
contract, even when capability selection would choose the compatibility path
at runtime.

## Per-frame pass order

1. `pipeline.begin_frame()` commits pending quality changes.
2. A resolution or profile change recalculates the XY tile grid and Z-slice
   count.
3. Existing extension SSBOs are resized only when their required byte size
   changes; missing buffers are allocated.
4. `cluster_build.cp` reconstructs view-space AABBs when the projection,
   near/far planes, resolution, tile size, or slice count changes. Camera view
   motion alone does not invalidate view-space bounds.
5. Selecting `cluster_assign.cp` makes the engine bind its `LightBuffer` UBO by
   reflected block name.
6. DRP binds its extension-owned cluster SSBOs at descriptor set 2.
7. `cluster_reset.cp` clears diagnostics and `cluster_assign.cp` intersects all
   active lights with every cluster, then writes compact indices and overflow.
8. Clustered materials derive the visible fragment's cluster and render an
   occupancy heatmap. Magenta means that cluster dropped one or more lights.

The heatmap uses a logarithmic occupancy scale, ranging from blue through green
and yellow to red. Gray surfaces belong to clusters with no lights, and dark
lines delineate XY tiles. It colors visible scene geometry rather than drawing
the cluster volumes into otherwise empty pixels. Set `lighting.cluster_debug =
false` through a profile or runtime override to inspect the provisional
clustered PBR output.

## GPU resources

All extension-owned buffers use descriptor set 2 and `std430` layout. Set 1 is
reserved for material resources, including the textures and uniform blocks
provided by asset-pbr. Keeping cluster storage in a separate set prevents
descriptor-type collisions when shader includes contribute additional resources.

| Binding | Resource | Contents |
| ---: | --- | --- |
| 0 | `cluster_bounds` | Two `vec4` values per XYZ cluster: minimum and maximum view-space bounds. |
| 2 | `cluster_metadata` | One `uvec2` per cluster: compact-list offset and count. |
| 3 | `cluster_light_indices` | Packed `uint` indices into the engine LightBuffer. |
| 4 | `cluster_counters` | Allocated-index, dropped-light, overflow-cluster, and max-candidate counters. |
| 5 | `cluster_overflow` | Number of dropped light candidates per cluster. |

The buffers are preserved across frames and resized only when the grid or
profile changes their required capacity. This debug milestone does not require
an intermediate render target or depth prepass.

## Quality and capability behavior

The clustered path is active when the selected profile has
`rendering.path = "forward_plus"`. It requires compute shaders and storage
buffers. If either capability is explicitly unavailable, quality resolution
falls back to `compatibility`, which renders conventional `model` materials.

Relevant profile settings are:

```lua
lighting = {
    cluster_tile_size = 96,
    cluster_z_slices = 16,
    max_lights_per_cluster = 64,
    cluster_debug = true,
}
```

## Using clustered materials

Assign the appropriate DRP material to each model material slot:

- `/drp/materials/clustered_opaque.material`
- `/drp/materials/clustered_mask.material`
- `/drp/materials/clustered_transparent.material`

The materials use asset-pbr's vertex and material conventions. Existing model
materials remain renderable, but are not clustered until their slots are
migrated.

## Recommended improvements

- Introduce reusable scene depth or a depth pyramid when conservative empty
  cluster rejection is implemented.
- Use conservative hierarchical depth to skip empty clusters without producing
  view-dependent holes.
- Rank overflowing local lights by estimated contribution instead of retaining
  the first 64 buffer entries.
- Add optional full-screen slice inspection and CPU-readable aggregate
  diagnostics; the current view visualizes the cluster selected by each visible
  fragment.
- Generate shader capacities from one build-time definition so the UBO view,
  profile validation, and material variants cannot drift.
- Add shadow indices and atlases as a separate feature consuming clustered
  light lists.
- Add WebGPU, Vulkan, Metal, and DirectX validation scenes and automated image
  comparisons.
