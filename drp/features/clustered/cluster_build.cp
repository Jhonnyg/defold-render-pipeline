#version 430

// Reconstructs one view-space AABB for every cell in the clustered-lighting
// grid. XY comes from screen tiles and Z uses logarithmic camera-depth slices.

layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;

uniform ClusterBuildParams
{
    highp mat4 inverse_projection;
    highp vec4 cluster_grid;
    highp vec4 cluster_screen;
    highp vec4 cluster_z_params;
};

struct ClusterBounds
{
    vec4 minimum;
    vec4 maximum;
};

layout(std430, set = 1, binding = 0) buffer ClusterBoundsBuffer
{
    ClusterBounds cluster_bounds[];
};

vec3 view_ray(vec2 ndc)
{
    // Unproject a point on the far clip plane; only the ray direction matters.
    vec4 position = inverse_projection * vec4(ndc, 1.0, 1.0);
    return position.xyz / position.w;
}

vec3 point_at_depth(vec3 ray, float depth)
{
    // Defold view space looks down -Z, while the depth values are positive.
    return ray * (-depth / ray.z);
}

void main()
{
    uvec3 cluster = gl_GlobalInvocationID.xyz;
    uvec3 dimensions = uvec3(cluster_grid.xyz);
    if (any(greaterThanEqual(cluster, dimensions)))
    {
        return;
    }

    vec2 screen_size = cluster_screen.xy;
    float tile_size = cluster_screen.z;
    vec2 pixel_min = vec2(cluster.xy) * tile_size;
    vec2 pixel_max = min(pixel_min + vec2(tile_size), screen_size);
    vec2 ndc_min = pixel_min / screen_size * 2.0 - 1.0;
    vec2 ndc_max = pixel_max / screen_size * 2.0 - 1.0;

    // Logarithmic slicing gives near-camera clusters much finer depth
    // resolution, where projected light volumes change most rapidly.
    float slice_min = float(cluster.z) / float(dimensions.z);
    float slice_max = float(cluster.z + 1u) / float(dimensions.z);
    float near_z = cluster_z_params.x;
    float far_z = cluster_z_params.y;
    float depth_min = near_z * pow(far_z / near_z, slice_min);
    float depth_max = near_z * pow(far_z / near_z, slice_max);

    vec3 minimum = vec3(3.402823e38);
    vec3 maximum = -minimum;
    // Each screen-tile corner defines a ray. Points at both slice depths form
    // the eight corners whose component-wise extrema produce the AABB.
    for (uint corner = 0u; corner < 4u; ++corner)
    {
        vec2 ndc = vec2(
            (corner & 1u) != 0u ? ndc_max.x : ndc_min.x,
            (corner & 2u) != 0u ? ndc_max.y : ndc_min.y
        );
        vec3 ray = view_ray(ndc);
        vec3 near_point = point_at_depth(ray, depth_min);
        vec3 far_point = point_at_depth(ray, depth_max);
        minimum = min(minimum, min(near_point, far_point));
        maximum = max(maximum, max(near_point, far_point));
    }

    // Cluster storage is X-major, followed by Y and then Z.
    uint cluster_index = cluster.x + dimensions.x *
        (cluster.y + dimensions.y * cluster.z);
    cluster_bounds[cluster_index].minimum = vec4(minimum, depth_min);
    cluster_bounds[cluster_index].maximum = vec4(maximum, depth_max);
}
