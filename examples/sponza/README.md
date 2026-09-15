# Sponza integration scene

This scene is DRP's visual integration test for actual clustered shading. Its
model and textures were carried over from the exploratory
`defold-clustered-rendering-2` project.

The source normal maps stored tangent-space X/Y only. Their blue channels are
expanded with a reconstructed positive Z because asset-pbr expects standard
RGB tangent-space normals.

It covers:

- asset-pbr metallic-roughness factors and textures;
- normal-mapped opaque geometry;
- alpha-masked geometry;
- directional and local lights;
- clustered light selection across a large scene; and
- a separate alpha-blended cube rendered after opaque and masked geometry.

The eight local point lights are animated by `animate_lights.script`. This is a
temporary integration test for per-frame LightBuffer updates and cluster-list
reassignment. Its speed and travel distance are script properties on the
`animate_lights` game object, and the test can be disabled with its `enabled`
property.

The normal `balanced` profile should show the lit Sponza scene. Set
`lighting.cluster_debug = true` through a DRP runtime override to inspect the
same geometry as a cluster occupancy heatmap.

The transparent cube is deliberately a simple pass-order fixture, not a
complete transparency-quality test. DRP does not yet sort multiple transparent
objects back-to-front.
