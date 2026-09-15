#ifndef DRP_CLUSTER_DEPTH_RANGE_GLSL
#define DRP_CLUSTER_DEPTH_RANGE_GLSL

#ifndef DEFOLD_PBR_INPUTS
in highp vec4 var_position;
#endif

uniform fs_drp_cluster_depth
{
    mat4 cluster_projection;
    vec4 cluster_grid;
    vec4 cluster_screen;
};

layout(std430, set = 2, binding = 1) buffer ClusterDepthRangesBuffer
{
    uvec2 cluster_depth_ranges[];
};

void drp_record_cluster_depth()
{
    // Derive the tile from the same projection-space equation as clustered
    // shading. This avoids render-texture origin differences between backends.
    vec4 clip = cluster_projection * vec4(var_position.xyz, 1.0);
    vec2 ndc = clip.xy / max(abs(clip.w), 0.000001);
    vec2 pixel = (ndc * 0.5 + 0.5) * cluster_screen.xy;
    pixel = clamp(pixel, vec2(0.0), cluster_screen.xy - vec2(0.5));
    uvec2 dimensions = uvec2(cluster_grid.xy);
    uvec2 tile = min(uvec2(pixel / cluster_screen.z), dimensions - 1u);
    uint tile_index = tile.x + dimensions.x * tile.y;

    // Positive IEEE-754 floats retain numeric ordering when represented as
    // uints, allowing portable integer atomics in a fragment shader.
    uint depth = floatBitsToUint(max(-var_position.z, 0.000001));
    atomicMin(cluster_depth_ranges[tile_index].x, depth);
    atomicMax(cluster_depth_ranges[tile_index].y, depth);
}

#endif
