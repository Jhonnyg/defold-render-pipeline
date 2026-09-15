#ifndef DRP_CLUSTER_DEPTH_ALPHA_GLSL
#define DRP_CLUSTER_DEPTH_ALPHA_GLSL

// Shared alpha-coverage helper for the masked and transparent cluster depth
// passes. It uses asset-pbr's canonical material declarations so the prepass
// cannot drift from the color pass's glTF material layout.

#include "/defold-pbr/shaders/pbr_material.glsl"

float drp_cluster_base_alpha()
{
    // Imported factors may contain unset/invalid data. Match asset-pbr's
    // default-factor handling before combining texture and vertex alpha.
    vec4 base_color = pbrMetallicRoughness.baseColorFactor;
    base_color = is_valid(base_color) && base_color.a > 0.0 ?
        base_color : vec4(1.0);
    if (pbrMetallicRoughness.metallicRoughnessTextures.x > 0.5)
    {
        base_color *= sample_base_color_texture();
    }
    return base_color.a * var_color.a;
}

#endif
