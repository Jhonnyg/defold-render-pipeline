#ifndef DRP_CLUSTERED_PBR_GLSL
#define DRP_CLUSTERED_PBR_GLSL

// The root shader includes the engine's glTF sampling and lighting modules.
// DRP changes punctual-light selection and visibility; material decoding, BRDF,
// ambient lighting and composition remain engine-owned.
#include "/drp/shaders/clustered_common.glsl"
#include "/drp/shaders/shadows.glsl"

layout(std430, set = 2, binding = 3) readonly buffer ClusterLightIndicesBuffer
{
    uint cluster_light_indices[];
};

PBRLightContribution drp_evaluate_clustered_lighting(MaterialInfo material, PBRSurface surface)
{
    PBRLightContribution total = pbr_create_light_contribution();
    uvec2 entry = cluster_metadata[drp_cluster_index(surface.position)];
    for (uint index = 0u; index < entry.y; ++index)
    {
        uint light_index = cluster_light_indices[entry.x + index];
        PBRLightSample light;
        sample_light(int(light_index), surface.position, var_view, light.direction, light.radiance);
        light.radiance *= drp_shadow_visibility(light_index, surface, lights[light_index].position.xyz);
        pbr_add_light_contribution(total, pbr_evaluate_light(material, surface, light));
    }
    return total;
}

#endif
