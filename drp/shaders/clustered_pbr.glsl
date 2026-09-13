#ifndef DRP_CLUSTERED_PBR_GLSL
#define DRP_CLUSTERED_PBR_GLSL

// Shared clustered-lighting implementation for the opaque, masked, and
// transparent PBR fragment shaders. It maps a view-space fragment to a cluster,
// reads that cluster's compact indices, and evaluates those engine UBO lights.

// The including root shader defines MAX_LIGHT_COUNT before asset-pbr imports
// the engine-owned LightBuffer. The engine buffer may be larger, never smaller.
#include "/defold-pbr/shaders/pbr_brdf.glsl"

layout(std430, set = 1, binding = 2) readonly buffer ClusterMetadataBuffer
{
    uvec2 cluster_metadata[];
};

layout(std430, set = 1, binding = 3) readonly buffer ClusterLightIndicesBuffer
{
    uint cluster_light_indices[];
};

uniform fs_drp_clustered
{
    mat4 cluster_projection;
    vec4 cluster_grid;
    vec4 cluster_screen;
    vec4 cluster_z_params;
};

struct ClusteredLightData
{
    vec3 diffuse;
    vec3 specular;
    vec3 emissive;
    float occlusion;
    float alpha;
};

ClusteredLightData empty_clustered_light_data()
{
    ClusteredLightData data;
    data.diffuse = vec3(0.0);
    data.specular = vec3(0.0);
    data.emissive = vec3(0.0);
    data.occlusion = 1.0;
    data.alpha = 1.0;
    return data;
}

void add_clustered_light_data(inout ClusteredLightData total, ClusteredLightData value)
{
    total.diffuse += value.diffuse;
    total.specular += value.specular;
}

float clustered_range_attenuation(float distance_to_light, float range)
{
    // Match asset-pbr's finite-range falloff so clustered and forward
    // materials react consistently to the same Defold light component.
    float normalized_distance = distance_to_light / max(range, PBR_EPSILON);
    float attenuation = saturate(1.0 - normalized_distance);
    return attenuation * attenuation;
}

ClusteredLightData evaluate_clustered_light(Light light, MaterialInfo material,
    vec3 normal, vec3 view, vec3 fragment_position)
{
    ClusteredLightData data = empty_clustered_light_data();
    int type = int(light.params.x);
    vec3 light_color = light.color.rgb * light.params.y;
    vec3 light_direction = vec3(0.0);
    float attenuation = 1.0;

    if (type == LIGHT_DIRECTIONAL)
    {
        light_direction = -world_to_view_dir(light.direction_range.xyz);
    }
    else
    {
        vec3 to_light = world_to_view_point(light.position.xyz) - fragment_position;
        float distance_to_light = length(to_light);
        light_direction = to_light / max(distance_to_light, PBR_EPSILON);
        attenuation = clustered_range_attenuation(distance_to_light, light.direction_range.w);

        if (type == LIGHT_SPOT)
        {
            // Defold stores full inner/outer cone angles. Half angles convert
            // them to the axis-to-edge angles used by the cosine test.
            vec3 spot_direction = world_to_view_dir(light.direction_range.xyz);
            float inner_cos = cos(0.5 * light.params.z - PBR_EPSILON);
            float outer_cos = cos(0.5 * light.params.w);
            attenuation *= smoothstep(outer_cos, inner_cos,
                dot(-light_direction, spot_direction));
        }
    }

    vec3 diffuse_light;
    vec3 specular_light;
    evaluate_brdf(material, normal, view, light_direction, light_color,
        diffuse_light, specular_light);
    data.diffuse = diffuse_light * attenuation;
    data.specular = specular_light * attenuation;
    return data;
}

uint clustered_index(vec3 fragment_position)
{
    uvec3 dimensions = uvec3(cluster_grid.xyz);

    // Project view-space position back to the same pixel grid used when the
    // compute pass built cluster bounds. Clamp edge pixels before integer cast.
    vec4 clip = cluster_projection * vec4(fragment_position, 1.0);
    vec2 ndc = clip.xy / max(abs(clip.w), PBR_EPSILON);
    vec2 pixel = (ndc * 0.5 + 0.5) * cluster_screen.xy;
    pixel = clamp(pixel, vec2(0.0), cluster_screen.xy - vec2(0.5));
    uvec2 tile = min(uvec2(pixel / cluster_screen.z), dimensions.xy - 1u);

    // Invert the logarithmic slice equation used by cluster_build.cp.
    float depth = max(-fragment_position.z, cluster_z_params.x);
    float slice = log(depth / cluster_z_params.x) /
        log(cluster_z_params.y / cluster_z_params.x);
    uint z = min(uint(clamp(slice, 0.0, 0.999999) * float(dimensions.z)),
        dimensions.z - 1u);
    return tile.x + dimensions.x * (tile.y + dimensions.y * z);
}

ClusteredLightData calculate_clustered_pbr_light_data(PBRParams params,
    MaterialInfo material, vec3 fragment_position)
{
    ClusteredLightData data = empty_clustered_light_data();
    data.alpha = material.baseColor.a;

    if (params.unlit)
    {
        data.diffuse = material.baseColor.rgb;
    }
    else
    {
        // Metadata stores the offset and count of this cluster's range inside
        // the global packed index buffer. Indices address the engine UBO.
        uvec2 entry = cluster_metadata[clustered_index(fragment_position)];
        for (uint index = 0u; index < entry.y; ++index)
        {
            uint light_index = cluster_light_indices[entry.x + index];
            add_clustered_light_data(data, evaluate_clustered_light(
                lights[light_index], material, params.normal, params.view,
                fragment_position));
        }

        // Ambient color is also supplied by the engine LightBuffer. The small
        // fallback prevents completely black unlit areas in this first pass.
        vec3 ambient = light_info.xyz + vec3(0.01);
        data.diffuse += material.diffuseColor * ambient;
        data.specular += material.f0 * ambient *
            (1.0 - 0.5 * material.perceptualRoughness);
        data.occlusion = get_occlusion(params);
    }

    data.emissive = get_emissive(params);
    return data;
}

vec3 composite_clustered_pbr(ClusteredLightData data)
{
    return (data.diffuse + data.specular) * data.occlusion + data.emissive;
}

#endif
