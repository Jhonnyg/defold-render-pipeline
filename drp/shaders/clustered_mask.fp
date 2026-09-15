#version 430

#include "/drp/shaders/clustered_config.glsl"

// Clustered PBR variant for alpha-masked geometry. It performs the material's
// cutoff test before lighting so discarded texels write neither color nor
// depth in either the heatmap or the provisional clustered-lighting path.

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

void main()
{
    PBRParams params = get_pbr_params();
    MaterialInfo material = get_material_info(params);
    // Keep this test identical to the model's material cutoff semantics.
    if (material.baseColor.a < params.alphaCutoff)
    {
        discard;
    }
#ifdef EDITOR
    PBRLightData data = calculate_pbr_light_data(params, material, var_position.xyz);
    out_fragColor = vec4(to_output(composite_pbr_light_data(data)), 1.0);
#else
    if (cluster_debug.x > 0.5)
    {
        out_fragColor = drp_cluster_debug_color(var_position.xyz);
        return;
    }
    PBRLightData data = calculate_clustered_pbr_light_data(params, material,
        var_position.xyz);
    out_fragColor = vec4(to_output(composite_pbr_light_data(data)), 1.0);
#endif
}
