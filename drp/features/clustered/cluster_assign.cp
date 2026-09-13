#version 430

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

const uint MAX_LIGHT_COUNT = 64u;
const uint MAX_CLUSTER_LIGHTS = 64u;

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
    Light lights[64];
};

struct ClusterBounds
{
    vec4 minimum;
    vec4 maximum;
};

layout(std430, set = 1, binding = 0) readonly buffer ClusterBoundsBuffer
{
    ClusterBounds cluster_bounds[];
};

layout(std430, set = 1, binding = 2) buffer ClusterMetadataBuffer
{
    uvec2 cluster_metadata[];
};

layout(std430, set = 1, binding = 3) buffer ClusterLightIndicesBuffer
{
    uint cluster_light_indices[];
};

layout(std430, set = 1, binding = 4) buffer ClusterCountersBuffer
{
    uint cluster_counters[4];
};

layout(std430, set = 1, binding = 5) buffer ClusterOverflowBuffer
{
    uint cluster_overflow[];
};

shared uint scan_values[64];
shared uint accepted_indices[64];
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

bool intersects_cluster(Light light, ClusterBounds bounds)
{
    uint type = uint(light.params.x + 0.5);
    if (type == 0u)
    {
        return true;
    }

    vec3 position = (view_matrix * vec4(light.position.xyz, 1.0)).xyz;
    float range = light.direction_range.w;
    if (type == 2u)
    {
        vec3 direction = normalize(mat3(view_matrix) * light.direction_range.xyz);
        return cone_aabb(position, direction, range, 0.5 * light.params.w,
            bounds.minimum.xyz, bounds.maximum.xyz);
    }
    return sphere_aabb(position, range, bounds.minimum.xyz, bounds.maximum.xyz);
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
    uint light_count = min(uint(light_info.w), MAX_LIGHT_COUNT);
    uint limit = min(uint(cluster_limits.x), MAX_CLUSTER_LIGHTS);

    // LightBuffer order is preserved. Directional lights match every cluster;
    // point and spot lights are culled against this cluster's bounds.
    bool matched = lane < light_count &&
        intersects_cluster(lights[lane], cluster_bounds[cluster_index]);
    uint prefix = inclusive_scan(matched ? 1u : 0u);

    if (matched && prefix <= limit)
    {
        accepted_indices[prefix - 1u] = lane;
    }
    barrier();

    if (lane == 0u)
    {
        // Atomically reserve this cluster's range in the global compact list.
        // Capacity checks keep metadata valid even if profile limits exceed a
        // device's maximum storage-buffer range.
        uint candidates = scan_values[gl_WorkGroupSize.x - 1u];
        uint stored = min(candidates, limit);
        uint offset = atomicAdd(cluster_counters[0], stored);
        uint capacity = uint(cluster_limits.y);
        uint writable = offset < capacity ? min(stored, capacity - offset) : 0u;
        uint dropped = candidates - writable;

        cluster_metadata[cluster_index] = uvec2(offset, writable);
        cluster_overflow[cluster_index] = dropped;
        atomicAdd(cluster_counters[1], dropped);
        if (dropped != 0u)
        {
            atomicAdd(cluster_counters[2], 1u);
        }
        atomicMax(cluster_counters[3], candidates);
        accepted_count = writable;
    }
    barrier();

    // Cooperatively copy the workgroup-local selection to the reserved range.
    uint output_offset = cluster_metadata[cluster_index].x;
    for (uint index = lane; index < accepted_count; index += gl_WorkGroupSize.x)
    {
        cluster_light_indices[output_offset + index] = accepted_indices[index];
    }
}
