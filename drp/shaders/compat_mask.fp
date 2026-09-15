#version 140

in mediump mat4 var_view;

#define MAX_LIGHT_COUNT 8
#include "/defold-pbr/shaders/pbr_lighting.glsl"

void main()
{
    PBRParams params = get_pbr_params();
    MaterialInfo material = get_material_info(params);
    if (material.baseColor.a < params.alphaCutoff)
    {
        discard;
    }
    PBRLightData data = calculate_pbr_light_data(params, material, var_position.xyz);
    out_fragColor = vec4(to_output(composite_pbr_light_data(data)), 1.0);
}
