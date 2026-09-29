#version 430

#include "/drp/shaders/clustered_config.glsl"

// Clustered PBR variant for alpha-blended geometry. Lighting remains linear
// until the final output conversion, and material alpha is preserved for the
// render script's source-alpha blending pass.

in mediump mat4 var_view;

#ifdef EDITOR
#define MAX_LIGHT_COUNT 8
#else
#define MAX_LIGHT_COUNT DRP_CLUSTER_LIGHT_CAPACITY
#endif

#ifdef EDITOR
#include "/defold-pbr/shaders/pbr_lighting.glsl"
#else
#include "/drp/shaders/clustered_pbr.glsl"
#endif

#include "/drp/shaders/output.glsl"

void main()
{
    PBRParams params = get_pbr_params();
    MaterialInfo material = get_material_info(params);
    // Avoid shading nearly invisible fragments and their full clustered list.
    if (material.baseColor.a <= 0.001)
    {
        discard;
    }
#ifdef EDITOR
    PBRLightData data = calculate_pbr_light_data(params, material, var_position.xyz);
    out_fragColor = vec4(drp_output(composite_pbr_light_data(data)), data.alpha);
#else
    if (cluster_debug.x > 0.5)
    {
        out_fragColor = drp_cluster_debug_color(var_position.xyz);
        return;
    }
    PBRLightData data = calculate_clustered_pbr_light_data(params, material,
        var_position.xyz);
    out_fragColor = vec4(drp_output(composite_pbr_light_data(data)), data.alpha);
#endif
}
