#version 430

#include "/drp/shaders/clustered_config.glsl"

// Builds the compact light list consumed by clustered fragment shaders.
// One workgroup handles one cluster, with one lane testing each entry in the
// engine-owned LightBuffer UBO against the cluster's view-space bounds.

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

uniform ClusterAssignParams
{
    highp mat4 view_matrix;
    highp vec4 cluster_grid;
    highp vec4 cluster_limits;
    highp vec4 cluster_z_params;
};

const uint MAX_LIGHT_COUNT = uint(DRP_CLUSTER_LIGHT_CAPACITY);
const uint MAX_CLUSTER_LIGHTS = uint(DRP_CLUSTER_LIST_CAPACITY);

struct Light
{
    vec4 position;
    vec4 color;
    vec4 direction_range;
    vec4 params;
};

// The engine recognizes this block by name and binds its existing std140 UBO.
// Cluster resources remain extension-owned SSBOs; light data is not copied.
layout(std140) uniform LightBuffer
{
    vec4 light_info;
    Light lights[DRP_CLUSTER_LIGHT_CAPACITY];
};

struct ClusterBounds
{
    vec4 minimum;
    vec4 maximum;
};

layout(std430, set = 2, binding = 0) readonly buffer ClusterBoundsBuffer
{
    ClusterBounds cluster_bounds[];
};

layout(std430, set = 2, binding = 1) readonly buffer ClusterDepthRangesBuffer
{
    uvec2 cluster_depth_ranges[];
};

layout(std430, set = 2, binding = 2) buffer ClusterMetadataBuffer
{
    uvec2 cluster_metadata[];
};

layout(std430, set = 2, binding = 3) buffer ClusterLightIndicesBuffer
{
    uint cluster_light_indices[];
};

layout(std430, set = 2, binding = 4) buffer ClusterCountersBuffer
{
    uint cluster_counters[4];
};

layout(std430, set = 2, binding = 5) buffer ClusterOverflowBuffer
{
    uint cluster_overflow[];
};

shared uint scan_values[DRP_CLUSTER_LIGHT_CAPACITY];
shared uint match_flags[DRP_CLUSTER_LIGHT_CAPACITY];
shared float candidate_scores[DRP_CLUSTER_LIGHT_CAPACITY];
shared uint accepted_indices[DRP_CLUSTER_LIST_CAPACITY];
shared uint accepted_count;

bool sphere_aabb(vec3 position, float radius, vec3 minimum, vec3 maximum)
{
    // Clamping the sphere center to the box gives the closest point on or in
    // the AABB. The sphere intersects when that point is inside its radius.
    vec3 distance = position - clamp(position, minimum, maximum);
    return dot(distance, distance) <= radius * radius;
}

bool cone_aabb(vec3 position, vec3 direction, float range, float half_angle,
    vec3 minimum, vec3 maximum)
{
    // Reject against the spotlight's range first. The remaining conservative
    // cone test uses the cluster's enclosing sphere to avoid false negatives.
    if (!sphere_aabb(position, range, minimum, maximum))
    {
        return false;
    }

    vec3 center = (minimum + maximum) * 0.5;
    vec3 extent = (maximum - minimum) * 0.5;
    float cluster_radius = length(extent);
    vec3 offset = center - position;
    float axial_center = dot(offset, direction);
    if (axial_center + cluster_radius < 0.0 || axial_center - cluster_radius > range)
    {
        return false;
    }

    vec3 radial_offset = offset - direction * axial_center;
    float radial_distance = length(radial_offset);
    float cone_radius = tan(half_angle) * clamp(axial_center, 0.0, range);
    return radial_distance <= cone_radius + cluster_radius;
}

bool evaluate_candidate(Light light, ClusterBounds bounds, out float score)
{
    uint type = uint(light.params.x + 0.5);
    if (type == 0u)
    {
        // Directional lights affect the whole view and must remain resident
        // when local lights overflow a cluster list.
        score = 1000000.0 + max(light.params.y, 0.0);
        return true;
    }

    vec3 position = (view_matrix * vec4(light.position.xyz, 1.0)).xyz;
    float range = light.direction_range.w;
    bool intersects;
    if (type == 2u)
    {
        vec3 direction = normalize(mat3(view_matrix) * light.direction_range.xyz);
        intersects = cone_aabb(position, direction, range, 0.5 * light.params.w,
            bounds.minimum.xyz, bounds.maximum.xyz);
    }
    else
    {
        intersects = sphere_aabb(position, range,
            bounds.minimum.xyz, bounds.maximum.xyz);
    }
    if (!intersects)
    {
        score = 0.0;
        return false;
    }

    vec3 center = (bounds.minimum.xyz + bounds.maximum.xyz) * 0.5;
    float cluster_radius = length(bounds.maximum.xyz - center);
    vec3 to_center = center - position;
    float center_distance = length(to_center);
    float surface_distance = max(center_distance - cluster_radius, 0.0);
    float attenuation = clamp(
        1.0 - surface_distance / max(range, 0.0001), 0.0, 1.0);
    float cone_weight = 1.0;
    if (type == 2u && center_distance > cluster_radius)
    {
        vec3 direction = normalize(mat3(view_matrix) * light.direction_range.xyz);
        float cone_cos = cos(0.5 * light.params.w);
        float alignment = dot(direction, to_center / center_distance);
        cone_weight = max(clamp(
            (alignment - cone_cos) / max(1.0 - cone_cos, 0.0001),
            0.0, 1.0), 0.05);
    }

    // This is only a residency estimate for overflowing clusters. Actual
    // shading still evaluates asset-pbr's complete attenuation and BRDF.
    float luminance = dot(max(light.color.rgb, vec3(0.0)),
        vec3(0.2126, 0.7152, 0.0722));
    score = luminance * max(light.params.y, 0.0) *
        attenuation * attenuation * cone_weight;
    return true;
}

uint inclusive_scan(uint value)
{
    // Hillis-Steele scan converts per-lane match flags into stable, one-based
    // output positions without serializing all 64 lanes on lane zero.
    uint lane = gl_LocalInvocationIndex;
    scan_values[lane] = value;
    barrier();
    for (uint offset = 1u; offset < gl_WorkGroupSize.x; offset <<= 1u)
    {
        uint addend = lane >= offset ? scan_values[lane - offset] : 0u;
        barrier();
        scan_values[lane] += addend;
        barrier();
    }
    return scan_values[lane];
}

void main()
{
    uint cluster_index = gl_WorkGroupID.x;
    uint cluster_count = uint(cluster_grid.x * cluster_grid.y * cluster_grid.z);
    if (cluster_index >= cluster_count)
    {
        return;
    }

    uint lane = gl_LocalInvocationIndex;
    uvec3 dimensions = uvec3(cluster_grid.xyz);
    uint tile_count = dimensions.x * dimensions.y;
    uint tile_index = cluster_index % tile_count;
    uvec2 depth_bits = cluster_depth_ranges[tile_index];
    ClusterBounds bounds = cluster_bounds[cluster_index];

    // The depth-range pass records every visible opaque, masked, and
    // transparent fragment. Clusters outside the tile's complete min/max span
    // cannot contribute to any fragment shaded this frame.
    bool active_cluster = depth_bits.x != 0xffffffffu &&
        bounds.maximum.w >= uintBitsToFloat(depth_bits.x) &&
        bounds.minimum.w <= uintBitsToFloat(depth_bits.y);
    if (!active_cluster)
    {
        if (lane == 0u)
        {
            cluster_metadata[cluster_index] = uvec2(0u);
            cluster_overflow[cluster_index] = 0u;
        }
        return;
    }

    uint light_count = min(uint(light_info.w), MAX_LIGHT_COUNT);
    uint limit = min(uint(cluster_limits.x), MAX_CLUSTER_LIGHTS);

    float score = 0.0;
    bool matched = lane < light_count &&
        evaluate_candidate(lights[lane], bounds, score);
    match_flags[lane] = matched ? 1u : 0u;
    candidate_scores[lane] = score;
    uint prefix = inclusive_scan(matched ? 1u : 0u);

    uint candidates = scan_values[gl_WorkGroupSize.x - 1u];
    if (candidates <= limit && matched)
    {
        accepted_indices[prefix - 1u] = lane;
    }
    barrier();

    if (lane == 0u)
    {
        // Overflow is uncommon, so rank only that path. Repeatedly selecting
        // the highest estimated contribution keeps the hot non-overflow path
        // fully parallel and gives deterministic LightBuffer-order tie breaks.
        uint stored = min(candidates, limit);
        if (candidates > limit)
        {
            for (uint output_index = 0u; output_index < stored; ++output_index)
            {
                uint best_index = MAX_LIGHT_COUNT;
                float best_score = -1.0;
                for (uint light_index = 0u; light_index < light_count; ++light_index)
                {
                    if (match_flags[light_index] != 0u &&
                        candidate_scores[light_index] > best_score)
                    {
                        best_index = light_index;
                        best_score = candidate_scores[light_index];
                    }
                }
                accepted_indices[output_index] = best_index;
                match_flags[best_index] = 0u;
            }
        }

        // Atomically reserve this cluster's range in the global compact list.
        // CPU configuration reserves cluster_count * limit entries, while the
        // remaining capacity check protects against contract drift.
        uint offset = atomicAdd(cluster_counters[0], stored);
        uint capacity = uint(cluster_limits.y);
        uint write_count = offset < capacity ? min(stored, capacity - offset) : 0u;
        uint dropped = candidates - write_count;

        cluster_metadata[cluster_index] = uvec2(offset, write_count);
        cluster_overflow[cluster_index] = dropped;
        atomicAdd(cluster_counters[1], dropped);
        if (dropped != 0u)
        {
            atomicAdd(cluster_counters[2], 1u);
        }
        atomicMax(cluster_counters[3], candidates);
        accepted_count = write_count;
    }
    barrier();

    // Cooperatively copy the workgroup-local selection to the reserved range.
    uint output_offset = cluster_metadata[cluster_index].x;
    for (uint index = lane; index < accepted_count; index += gl_WorkGroupSize.x)
    {
        cluster_light_indices[output_offset + index] = accepted_indices[index];
    }
}
