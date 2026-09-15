#ifndef DRP_CLUSTER_DEPTH_ALPHA_GLSL
#define DRP_CLUSTER_DEPTH_ALPHA_GLSL

#include "/defold-pbr/shaders/pbr_material.glsl"

float drp_cluster_base_alpha()
{
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
