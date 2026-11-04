# Clustered Lighting Feature

## Status

The clustered renderer is functionally complete for the current MVP1 scope.
Development is paused pending code review and eventual integration into the
master branch. The remaining items below are validation and hardening work;
they do not require another lighting-feature redesign.

The complete pass and resource contract is documented in
[`docs/CLUSTERED_LIGHTING.md`](../../../docs/CLUSTERED_LIGHTING.md).

## Implemented MVP1 functionality

- Forward+ frustum partitioning with screen tiles and logarithmic Z slices.
- View-space cluster AABB construction.
- Directional, point, and conservative spot-light assignment.
- Engine-owned `LightBuffer` UBO consumption from compute and fragment stages.
- Extension-owned cluster bounds, metadata, index, counter, overflow, and
  depth-range SSBOs.
- Persistent allocation and resizing after viewport/profile changes.
- Uniform per-cluster capacity reduction when device buffer limits require it.
- Contribution-ranked selection when a cluster exceeds its light-list limit.
- Conservative visible tile depth ranges for rejecting empty Z slices.
- Built-in glTF metallic-roughness shading for opaque and alpha-masked geometry.
- Basic transparent clustered shading with depth writes disabled and explicit
  back-to-front render-entry sorting.
- Conventional compatibility rendering without duplicate scenes.
- A compatibility-only export for devices unable to load compute/SSBO shaders.
- Perspective and orthographic cluster bounds; clip ranges crossing the eye
  use conventional shading because logarithmic slicing needs positive depth.
- Animated/per-frame light reassignment.
- Surface occupancy and overflow heatmap.
- Public CPU-visible grid, capacity, workload, and allocation diagnostics.

## Remaining before an MVP1 PR/release

### Automated coverage

Internal development checks cover dispatch limits, capability fallback,
projection changes, light assignment, compatibility exports, and resource
lifetime. They are maintained locally and are not part of the library.
Backend image comparisons and GPU synchronization checks remain separate.

### Runtime stress testing

- Repeatedly resize and switch between Forward+ and compatibility profiles.
- Exercise hot reload, projection changes, near/far changes, zero lights,
  maximum lights, deliberate overflow, finalization, and reinitialization.
- Verify that storage use stabilizes and deleted handles are never rebound.

### Backend validation

- Manually verify the intended Metal, Vulkan, DirectX, and WebGPU targets.
- Capture normal shading and heatmap output for comparison.
- Verify masks, transparency, animated lights, resize, and profile switching on
  every supported backend.

### Performance baseline

- Capture reset, depth-range, bounds, assignment, opaque, mask, and transparent
  GPU timings independently.
- Compare representative resolutions, profiles, and light counts.
- Confirm that the depth-range pass is a net benefit for representative scenes.

### Packaging contract

- Record the minimum Defold revision containing the required SSBO and
  `LightBuffer` support.
- Finalize required `game.project` settings and dependency versions.
- Review the public Lua diagnostics/API and the native bridge before merging.

## Deferred and non-blocking

- Native glTF opaque/mask/transparent material selection. This is proposed as
  an engine feature in
  [`docs/GLTF_PBR_SURFACE_MODES.md`](../../../docs/GLTF_PBR_SURFACE_MODES.md).
- Public engine capability/limit APIs and removal of DRP's temporary private
  declarations.
- Cleanup of misleading engine SSBO reflection warnings.
- Hierarchical scene depth or a reusable depth pyramid.
- Order-independent transparency.
- Asynchronous GPU counter readback.
- A dedicated full-screen cluster/Z-slice inspector.
- Shadows, ambient occlusion, and further post-processing; these are separate DRP
  features rather than clustered-lighting MVP1 requirements.
