#version 430

#include "/drp/shaders/clustered_config.glsl"

// Resets the global allocation and diagnostic counters before cluster light
// assignment. Cluster metadata itself is overwritten by cluster_assign.cp.

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

uniform ClusterResetParams
{
    highp vec4 cluster_grid;
};

layout(std430, set = 2, binding = 1) buffer ClusterDepthRangesBuffer
{
    // Positive float depths represented as uints so fragment shaders can use
    // portable atomicMin/atomicMax operations.
    uvec2 cluster_depth_ranges[];
};

layout(std430, set = 2, binding = 4) buffer ClusterCountersBuffer
{
    // Allocated indices, dropped lights, overflowing clusters, and maximum
    // candidate count observed in one cluster.
    uint cluster_counters[4];
};

void main()
{
    uint index = gl_GlobalInvocationID.x;
    uint tile_count = uint(cluster_grid.x * cluster_grid.y);
    if (index < tile_count)
    {
        cluster_depth_ranges[index] = uvec2(0xffffffffu, 0u);
    }
    if (index == 0u)
    {
        cluster_counters[0] = 0u;
        cluster_counters[1] = 0u;
        cluster_counters[2] = 0u;
        cluster_counters[3] = 0u;
    }
}
