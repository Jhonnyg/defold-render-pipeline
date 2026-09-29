#version 140

// Conventional asset-pbr lighting used as a render-time material override when
// a clustered-authored scene runs under the compatibility profile.

in mediump mat4 var_view;

#define MAX_LIGHT_COUNT 8
#include "/defold-pbr/shaders/pbr_lighting.glsl"

#include "/drp/shaders/output.glsl"

void main()
{
    PBRParams params = get_pbr_params();
    MaterialInfo material = get_material_info(params);
    PBRLightData data = calculate_pbr_light_data(params, material, var_position.xyz);
    out_fragColor = vec4(drp_output(composite_pbr_light_data(data)), 1.0);
}
