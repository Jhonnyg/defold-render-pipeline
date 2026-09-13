#version 430

// Resets the global allocation and diagnostic counters before cluster light
// assignment. Cluster metadata itself is overwritten by cluster_assign.cp.

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(std430, set = 1, binding = 4) buffer ClusterCountersBuffer
{
    // Allocated indices, dropped lights, overflowing clusters, and maximum
    // candidate count observed in one cluster.
    uint cluster_counters[4];
};

void main()
{
    cluster_counters[0] = 0u;
    cluster_counters[1] = 0u;
    cluster_counters[2] = 0u;
    cluster_counters[3] = 0u;
}
