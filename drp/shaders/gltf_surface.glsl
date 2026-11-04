#ifndef DRP_GLTF_SURFACE_GLSL
#define DRP_GLTF_SURFACE_GLSL

#include "/builtins/materials/gltf_sampling.glsl"

// DRP material tags choose the render pass until automatic glTF surface routing
// is available. Keep that explicit choice identical in color, depth and shadows.
PBRMaterial drp_sample_material(int alpha_mode)
{
    PBRMaterial material = pbr_sample_material(var_texcoord0, var_color);
    material.alphaMode = alpha_mode;
    return material;
}

bool drp_should_discard(PBRMaterial material)
{
    return (!material.doubleSided && !gl_FrontFacing)
        || pbr_should_discard_alpha(material)
        || (material.alphaMode == PBR_ALPHA_BLEND && material.baseColor.a <= 0.001);
}

#endif
