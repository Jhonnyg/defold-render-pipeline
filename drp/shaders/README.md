# Shaders

DRP uses Defold's modular built-in glTF shaders. The editor, Bob and engine must
come from a build containing these modules; the external asset-pbr dependency
and its view-helper adapter are no longer used. Compute programs remain with
their owning feature.

| Responsibility | Implementation |
| --- | --- |
| Vertex positions, normals, tangent frame and varyings | `/builtins/materials/gltf.vp` and `gltf_vertex*.glsl` |
| Imported material factors, texture sampling and normal maps | `/builtins/materials/gltf_sampling.glsl` |
| Surface construction, BRDF inputs, alpha and color conversion | `/builtins/materials/gltf_common.glsl`, `gltf_material.glsl` |
| GGX/Lambert BRDF, light sampling, ambient and composition | `/builtins/materials/gltf_brdf.glsl`, `gltf_lighting.glsl`, `lighting.glsl` |
| Explicit opaque/mask/transparent pass selection and coverage | `gltf_surface.glsl` |
| Compact light selection | `clustered_pbr.glsl` |
| Per-light shadow visibility | `shadows.glsl` |
| Linear HDR or sRGB scene output | `output.glsl` |

The clustered loop calls `sample_light()` for each compact engine light index,
multiplies its radiance by shadow visibility, and evaluates the built-in BRDF.
Conventional compatibility and editor previews use the engine's direct-light
loop. Both paths use engine ambient lighting and `pbr_compose_lighting()`.
Material AO attenuates indirect lighting only. Emission remains unshadowed;
unlit materials output their base color. HDR retains linear scene values until
the tone-map pass; LDR/editor output uses `pbr_linear_to_srgb()`.

## Surface coverage

Models still select DRP's explicit opaque, mask or transparent material. The
shared adapter sets `PBRMaterial.alphaMode` from that pass, preserving authored
routing even if an imported material's alpha mode differs. Automatic routing
from glTF metadata is a separate integration task.

Color, cluster-depth and shadow passes use the same built-in material sampler
and coverage helper. They preserve zero base-color factors and zero alpha,
vertex alpha, texture alpha, and the imported cutoff. The visible pass samples
normal maps before discarding so texture derivatives remain valid at cutouts.
Unused texture samples in depth/shadow shaders are eliminated by the compiler.
DRP disables hardware culling for its surface passes and uses glTF's
`doubleSided` flag for fragment sidedness; the engine also flips back-face
normals for double-sided lighting. Transparent surfaces receive shadows but
still do not cast them.

## Upgrade behavior

This follows the engine's glTF material contract rather than asset-pbr's old
fallbacks. Zero factors remain zero, material AO does not darken direct lights,
and emissive/unlit handling follows the built-in shader. Those corrections may
change the appearance of existing scenes. Existing model material paths and
sampler names stay unchanged.

The bundled materials still use the non-skinned, non-instanced `gltf.vp`.
Custom skinning, instancing or deformation needs matching vertex programs in
all color, depth and shadow passes; switching to the built-ins does not add
those rendering variants automatically.
