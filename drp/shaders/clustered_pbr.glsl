#ifndef DRP_CLUSTERED_PBR_GLSL
#define DRP_CLUSTERED_PBR_GLSL

// Shared clustered-lighting implementation for the opaque, masked, and
// transparent PBR fragment shaders. It maps a view-space fragment to a cluster,
// reads that cluster's compact indices, and evaluates those engine UBO lights.

// asset-pbr owns the metallic-roughness material decoding, GGX/Lambert BRDF,
// Defold light evaluation, indirect fallback, and final composition. DRP only
// replaces its all-lights loop with a lookup through the compact list for the
// fragment's cluster. The including root defines MAX_LIGHT_COUNT before
// asset-pbr imports the engine-owned LightBuffer.
#include "/defold-pbr/shaders/pbr_lighting.glsl"
#include "/drp/shaders/clustered_common.glsl"

layout(std430, set = 2, binding = 3) readonly buffer ClusterLightIndicesBuffer
{
    uint cluster_light_indices[];
};

PBRLightData calculate_clustered_pbr_light_data(PBRParams params,
    MaterialInfo material, vec3 fragment_position)
{
    PBRLightData data = empty_pbr_light_data();
    data.alpha = material.baseColor.a;

    if (params.unlit)
    {
        data.diffuse = material.baseColor.rgb;
    }
    else
    {
        // Metadata stores the offset and count of this cluster's range inside
        // the global packed index buffer. Indices address the engine UBO.
        uvec2 entry = cluster_metadata[drp_cluster_index(fragment_position)];
        for (uint index = 0u; index < entry.y; ++index)
        {
            uint light_index = cluster_light_indices[entry.x + index];
            Light light = lights[light_index];
            add_pbr_light_data(data, evaluate_light(
                light.position,
                light.color,
                light.direction_range,
                light.params,
                material,
                params.normal,
                params.view,
                fragment_position));
        }

        // Keep constant indirect light identical to asset-pbr's conventional
        // forward path; only punctual-light selection differs.
        add_pbr_light_data(data, evaluate_constant_indirect(material));
        data.occlusion = get_occlusion(params);
    }

    data.emissive = get_emissive(params);
    return data;
}

#endif
