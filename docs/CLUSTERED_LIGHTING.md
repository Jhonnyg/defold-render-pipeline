# Clustered Lighting

## Scope

The DRP Forward+ path partitions the camera frustum into screen-space tiles and
logarithmic depth slices. A compute pass intersects every active engine light
with the resulting view-space cluster bounds and writes compact per-cluster
lists. Opaque, alpha-masked, and transparent materials then use the list for
their fragment's cluster rather than iterating every active light.

The clustered materials include asset-pbr's `pbr_lighting.glsl`. Asset-pbr
therefore remains authoritative for glTF metallic-roughness material decoding,
normal mapping, GGX/Lambert BRDF evaluation, Defold light evaluation, constant
indirect light, and final composition. DRP only replaces the all-lights loop
with the compact index range selected by the fragment's cluster. An optional
surface-projected heatmap remains available for assignment diagnostics.

This iteration supports directional, point, and spot assignment, direct
metallic-roughness shading, contribution-based overflow selection, conservative
tile depth-range rejection, runtime compatibility material overrides, and a
surface-projected diagnostic heatmap. It does not yet include shadows,
image-based lighting, HDR output, post-processing, or temporal reuse.

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
project uses `[light] max_count = 64`; a larger engine allocation may also be
bound to this smaller shader declaration.

CPU limits live in `/drp/features/clustered/config.lua`, and
`/drp/shaders/clustered_config.glsl` supplies matching compile-time shader
constants. Defold cannot yet generate Lua and GLSL constants from one source,
so both files carry an explicit synchronization comment. Runtime profile values
are always clamped against the Lua contract.

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
5. `cluster_reset.cp` resets global counters and per-tile depth ranges.
6. Opaque and masked geometry populate hardware depth. Visible opaque, masked,
   and transparent fragments atomically accumulate their tile's minimum and
   maximum positive view depth while color writes are disabled.
7. Selecting `cluster_assign.cp` makes Defold bind its `LightBuffer` UBO by
   reflected block name, while DRP binds its SSBOs at descriptor set 2.
8. Assignment rejects slices outside their tile's visible depth span,
   intersects lights with active clusters, prioritizes candidates, and writes
   compact indices and overflow data.
9. Clustered opaque and masked materials reuse the prepass depth.
10. Conventional `model` materials use regular forward lighting.
11. Clustered transparent materials render last, explicitly sorted back to
    front, with source-alpha blending and depth writes disabled.

Actual clustered shading is the default. Set `lighting.cluster_debug = true`
through a profile or runtime override to replace it with a logarithmic
occupancy scale ranging from blue through green and yellow to red. Gray surfaces
belong to clusters with no lights, magenta means the cluster dropped one or
more candidates, and dark lines delineate XY tiles. The diagnostic colors
visible scene geometry rather than drawing cluster volumes into otherwise
empty pixels.

## GPU resources

All extension-owned buffers use descriptor set 2 and `std430` layout. Set 1 is
reserved for material resources, including the textures and uniform blocks
provided by asset-pbr. Keeping cluster storage in a separate set prevents
descriptor-type collisions when shader includes contribute additional resources.

| Binding | Resource | Contents |
| ---: | --- | --- |
| 0 | `cluster_bounds` | Two `vec4` values per XYZ cluster: minimum and maximum view-space bounds. |
| 1 | `cluster_depth_ranges` | One `uvec2` per XY tile: atomic min/max positive view depth encoded as float bits. |
| 2 | `cluster_metadata` | One `uvec2` per cluster: compact-list offset and count. |
| 3 | `cluster_light_indices` | Packed `uint` indices into the engine LightBuffer. |
| 4 | `cluster_counters` | Allocated-index, dropped-light, overflow-cluster, and max-candidate counters. |
| 5 | `cluster_overflow` | Number of dropped light candidates per cluster. |

The buffers are preserved across frames and resized only when the grid or
profile changes their required capacity. The depth-range pass reuses the default
target's hardware depth attachment and disables color writes, so it does not
allocate a full-resolution color target or depth pyramid.

The global compact list is sized as
`cluster_count * effective_max_lights_per_cluster`. If the device's maximum
storage-buffer range cannot hold the requested limit, DRP reduces the limit
uniformly for every cluster. This avoids an order-dependent truncated buffer in
which early workgroups could consume all storage and starve later screen areas.

## Quality and capability behavior

The clustered path is active when the selected profile has
`rendering.path = "forward_plus"`. It requires compute shaders and storage
buffers. If either capability is explicitly unavailable, quality resolution
falls back to `compatibility`. Conventional `model` materials render normally,
while clustered predicates use matching conventional asset-pbr overrides so
the same scene works with either path.

Relevant profile settings are:

```lua
lighting = {
    cluster_tile_size = 96,
    cluster_z_slices = 16,
    max_lights_per_cluster = 64,
    cluster_debug = false,
}
```

## Using clustered materials

Assign the appropriate DRP material to each model material slot:

- `/drp/materials/clustered_opaque.material`
- `/drp/materials/clustered_mask.material`
- `/drp/materials/clustered_transparent.material`

The materials use asset-pbr's vertex shader and include its complete lighting
module. Existing conventional model materials remain renderable on the forward
path, but are not clustered until their slots are migrated.

Opaque and alpha-mask slots render before transparent slots. The mask shader
performs the glTF alpha-cutoff test before shading. The transparent shader
preserves material alpha, renders with depth writes disabled, and explicitly
requests Defold's back-to-front world-entry sort. Sorting occurs at render-entry
positions; intersecting meshes and triangles within one model still require an
order-independent transparency technique for perfect results.

The Sponza collection under `/examples/sponza` is the visual integration test.
It contains opaque and masked Sponza slots, a transparent fixture, a directional
light, and local lights distributed through the atrium.

## Automatic profile material selection

Selection occurs in the render script rather than by mutating model components.
A model retains its clustered material and opaque/mask/transparent predicate:

- Forward+ draws the original material with cluster SSBOs.
- Compatibility selects a matching conventional asset-pbr render resource with
  `render.enable_material()`, draws the same predicate, and disables the
  override afterward.
- Model textures and per-model material constants remain on the render entry
  and match the override by sampler and constant name.

This lets one content scene switch profiles at a frame boundary without walking
components or replacing material URLs. Cluster materials must still be
buildable for the target. A future engine material-variant resource could allow
the bundler to omit unsupported shader variants entirely.

This runtime selection does not yet infer the original clustered material for a
newly imported model. The intended authoring-side solution is an editor/build
adapter that reads each imported material's alpha mode and PBR feature metadata,
maps it to the opaque, mask, or transparent DRP material family, and preserves
an explicit per-slot user override. The scene stores the semantic DRP family,
not a profile-specific duplicate; profile resolution then chooses clustered or
conventional programs at draw time as described above. Keeping import inference
outside the render loop avoids component traversal and URL mutation every frame.

That responsibility is now proposed as native Defold glTF/PBR functionality
rather than a DRP-specific importer. See
[`GLTF_PBR_SURFACE_MODES.md`](GLTF_PBR_SURFACE_MODES.md) for the deferred engine
design.

## Depth-aware assignment and performance

The depth pass records a conservative min/max span for every XY tile. Opaque and
masked draws populate hardware depth. Transparent draws test against that depth
without writing it, so visible transparent layers widen the range. Assignment
skips a logarithmic Z slice only when it lies entirely outside the complete
span. Every slice between the extrema remains active, so disjoint or occluded
surfaces cannot create holes; dense tiles simply receive less optimization.

No full-resolution color-depth texture is allocated. Fragment shaders encode
positive depth as `uint` and update the tile SSBO with integer atomics. They
derive tile coordinates from the same projection equation used by clustered
shading, avoiding render-texture origin differences across backends.

The maximum assignment workload is `cluster_count * 64` intersection tests.
`drp.get_feature_diagnostics("clustered")` returns that bound, grid dimensions,
effective capacities, buffer sizes, and device-limit clamping. Actual work is
lower because empty tiles and inactive slices return before testing lights.

When a cluster overflows, directional lights are retained first and local
lights are ranked by estimated luminance, intensity, distance, range overlap,
and spotlight alignment. Equal-score ties retain LightBuffer order. Exact
asset-pbr lighting remains in the fragment shader; the estimate only decides
residency.

## Validation plan

Validation should be split into three layers:

1. Pure Lua tests validate grid dimensions, uniform device-limit clamping,
   allocation sizes, profile transitions, and diagnostic snapshots without a
   graphics context.
2. Shader/reference tests compare logarithmic slices, projection-space tile
   selection, AABB construction, point/sphere intersection, conservative cone
   intersection, contribution ordering, and float-bit depth ranges with small
   CPU reference cases. Boundaries include near/far planes, exact tile edges,
   empty tiles, equal-score ties, and one-entry overflow.
3. GPU integration tests render deterministic small scenes and Sponza while
   changing resolution, projection, profile, camera transform, and animated
   lights. Captures verify PBR shading, occupancy, magenta overflow,
   compatibility overrides, alpha masks, and overlapping transparent objects.

Lifecycle stress tests should repeatedly resize and switch profiles, then
verify that storage use stabilizes and deleted handles are not rebound.
Performance captures should measure reset, depth-range, bounds, assignment,
opaque, mask, and transparent passes separately at representative resolution
and light tiers. Backend coverage is manual for the current milestone.

## Recommended improvements

- Replace conservative tile spans with reusable hierarchical depth when later
  effects also require scene depth.
- Generate Lua and shader capacities from one build-time definition when Defold
  exposes a suitable build hook.
- Add weighted blended order-independent transparency for intersecting meshes
  and triangle-level ordering that object sorting cannot solve.
- Expose asynchronous storage-buffer readback so exact GPU counters can be
  returned through the diagnostics API.
- Add a dedicated full-screen Z-slice inspector; the current heatmap overlays
  occupancy on visible scene surfaces.
- Add shadow indices and atlases as a separate feature consuming clustered
  light lists.
- Add WebGPU, Vulkan, Metal, and DirectX validation scenes and automated image
  comparisons.
