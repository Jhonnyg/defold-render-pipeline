# Sponza integration scene

This scene is DRP's visual integration test for actual clustered shading. Its
model and textures were carried over from the exploratory
`defold-clustered-rendering-2` project.

It covers:

- asset-pbr metallic-roughness factors and textures;
- normal-mapped opaque geometry;
- alpha-masked geometry;
- directional and local lights;
- clustered light selection across a large scene; and
- a separate alpha-blended cube rendered after opaque and masked geometry.

The normal `balanced` profile should show the lit Sponza scene. Set
`lighting.cluster_debug = true` through a DRP runtime override to inspect the
same geometry as a cluster occupancy heatmap.

The transparent cube is deliberately a simple pass-order fixture, not a
complete transparency-quality test. DRP does not yet sort multiple transparent
objects back-to-front.
