#version 430

// Reduces the full-resolution linear-depth prepass to one minimum/maximum
// visible depth range per XY tile. The ranges are currently diagnostic data
// and are reserved for a future conservative cluster-pruning pass.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

uniform sampler2D depth_texture;
uniform ClusterDepthParams
{
    highp vec4 cluster_grid;
    highp vec4 cluster_screen;
    highp vec4 cluster_z_params;
};

layout(std430, set = 1, binding = 1) buffer ClusterDepthRangesBuffer
{
    // x/y: minimum/maximum visible view depth; z: geometry-present flag.
    vec4 cluster_depth_ranges[];
};

void main()
{
    uvec2 tile = gl_GlobalInvocationID.xy;
    uvec2 dimensions = uvec2(cluster_grid.xy);
    if (any(greaterThanEqual(tile, dimensions)))
    {
        return;
    }

    ivec2 screen_size = ivec2(cluster_screen.xy);
    int tile_size = int(cluster_screen.z);
    ivec2 pixel_min = ivec2(tile) * tile_size;
    ivec2 pixel_max = min(pixel_min + ivec2(tile_size), screen_size);

    float minimum_depth = cluster_z_params.y;
    float maximum_depth = cluster_z_params.x;
    bool has_geometry = false;

    // One invocation owns an entire tile. This simple first implementation is
    // intentionally deterministic; a later version can reduce pixels in
    // parallel or source the range from a hierarchical depth texture.
    for (int y = pixel_min.y; y < pixel_max.y; ++y)
    {
        for (int x = pixel_min.x; x < pixel_max.x; ++x)
        {
            // Render-target rows use an upper-left image origin, while cluster
            // Y and fragment coordinates grow from the bottom of the viewport.
            int source_y = screen_size.y - 1 - y;
            vec2 uv = (vec2(x, source_y) + 0.5) / vec2(screen_size);
            float linear_depth = textureLod(depth_texture, uv, 0.0).r;
            if (linear_depth > 0.0)
            {
                minimum_depth = min(minimum_depth, linear_depth);
                maximum_depth = max(maximum_depth, linear_depth);
                has_geometry = true;
            }
        }
    }

    // A zero vector distinguishes empty tiles from valid positive view depth.
    uint tile_index = tile.x + dimensions.x * tile.y;
    cluster_depth_ranges[tile_index] = has_geometry
        ? vec4(minimum_depth, maximum_depth, 1.0, 0.0)
        : vec4(0.0);
}
