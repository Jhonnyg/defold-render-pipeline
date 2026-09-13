# Clustered Lighting

## Scope

The initial DRP Forward+ path partitions the camera frustum into screen-space
tiles and logarithmic depth slices. A compute pass intersects every active
engine light with the resulting view-space cluster bounds and writes compact
per-cluster lists. Clustered PBR fragment shaders evaluate only the indices in
the fragment's cluster.

This iteration supports directional, point, and spot lights. It does not yet
include shadows, image-based lighting, HDR output, post-processing, light-list
prioritization, or temporal reuse.

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

1. The active camera supplies view/projection matrices and near/far distances.
2. Clustered opaque and masked models render linear view depth into an
   `RGBA32F` color target with a depth attachment.
3. `cluster_depth_reduce.cp` computes one visible depth range per XY tile. The
   data is retained for diagnostics and a future conservative depth-pruning
   implementation; the current assignment pass does not reject clusters from
   it because a single-layer depth prepass cannot represent occluded layers.
4. `cluster_reset.cp` clears global list counters.
5. `cluster_build.cp` reconstructs one view-space AABB for every XYZ cluster.
6. `cluster_assign.cp` reads the engine `LightBuffer` UBO, intersects its lights
   with every cluster, and writes metadata plus compact light indices.
7. Clustered opaque, masked, and transparent material passes look up the
   fragment's cluster and evaluate its PBR light list.
8. Conventional `model` materials are also drawn during migration, but they use
   their own forward lighting path and do not consume cluster lists.

## GPU resources

All extension-owned buffers use descriptor set 1 and `std430` layout.

| Binding | Resource | Contents |
| ---: | --- | --- |
| 0 | `cluster_bounds` | Two `vec4` values per XYZ cluster: minimum and maximum view-space bounds. |
| 1 | `cluster_depth_ranges` | One `vec4` per XY tile: visible min/max depth and geometry flag. |
| 2 | `cluster_metadata` | One `uvec2` per cluster: compact-list offset and count. |
| 3 | `cluster_light_indices` | Packed `uint` indices into the engine LightBuffer. |
| 4 | `cluster_counters` | Allocated-index, dropped-light, overflow-cluster, and max-candidate counters. |
| 5 | `cluster_overflow` | Number of dropped light candidates per cluster. |

The buffers are resized on viewport or quality-profile changes. The linear
depth render target is full resolution in this first version.

## Quality and capability behavior

The clustered path is active when the selected profile has
`rendering.path = "forward_plus"`. It requires compute shaders, storage buffers,
and a float render target. If those capabilities are explicitly unavailable,
quality resolution falls back to `compatibility`, which renders conventional
`model` materials.

Relevant profile settings are:

```lua
lighting = {
    cluster_tile_size = 96,
    cluster_z_slices = 16,
    max_lights_per_cluster = 64,
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

- Replace the full-resolution linear-depth prepass with reusable scene depth or
  a depth pyramid once the pipeline has a shared depth contract.
- Use conservative hierarchical depth to skip empty clusters without producing
  view-dependent holes.
- Rank overflowing local lights by estimated contribution instead of retaining
  the first 64 buffer entries.
- Add cluster occupancy and overflow debug views plus GPU timing counters.
- Generate shader capacities from one build-time definition so the UBO view,
  profile validation, and material variants cannot drift.
- Add shadow indices and atlases as a separate feature consuming clustered
  light lists.
- Add WebGPU, Vulkan, Metal, and DirectX validation scenes and automated image
  comparisons.
