#ifndef DRP_CLUSTERED_COMMON_GLSL
#define DRP_CLUSTERED_COMMON_GLSL

// Shared fragment-side cluster lookup and diagnostic visualization. The
// compute builder uses the same X-major layout and logarithmic Z equation.

layout(std430, set = 2, binding = 2) readonly buffer ClusterMetadataBuffer
{
    // x: offset into ClusterLightIndicesBuffer; y: stored light count.
    uvec2 cluster_metadata[];
};

layout(std430, set = 2, binding = 5) readonly buffer ClusterOverflowBuffer
{
    // Number of candidates dropped by the per-cluster or global capacity.
    uint cluster_overflow[];
};

uniform fs_drp_clustered
{
    mat4 cluster_projection;
    vec4 cluster_grid;
    vec4 cluster_screen;
    vec4 cluster_z_params;
    // x: show occupancy/overflow instead of final PBR lighting.
    vec4 cluster_debug;
};

uint drp_cluster_index(vec3 view_position)
{
    uvec3 dimensions = uvec3(cluster_grid.xyz);

    // Project back onto the same bottom-left NDC grid used by the AABB builder.
    // Projection-based lookup stays consistent across graphics backends whose
    // framebuffer coordinate origins may differ.
    vec4 clip = cluster_projection * vec4(view_position, 1.0);
    vec2 ndc = clip.xy / max(abs(clip.w), 0.000001);
    vec2 pixel = (ndc * 0.5 + 0.5) * cluster_screen.xy;
    pixel = clamp(pixel, vec2(0.0), cluster_screen.xy - vec2(0.5));
    uvec2 tile = min(uvec2(pixel / cluster_screen.z), dimensions.xy - 1u);

    // This is the inverse of depth = near * pow(far / near, slice).
    float near_z = cluster_z_params.x;
    float far_z = cluster_z_params.y;
    float depth = clamp(-view_position.z, near_z, far_z);
    float slice = log(depth / near_z) / log(far_z / near_z);
    uint z = min(uint(clamp(slice, 0.0, 0.999999) * float(dimensions.z)),
        dimensions.z - 1u);

    return tile.x + dimensions.x * (tile.y + dimensions.y * z);
}

vec3 drp_cluster_heat(float occupancy)
{
    // Blue -> cyan -> green -> yellow -> red gives low counts more visual
    // separation than a linear grayscale ramp.
    return clamp(vec3(
        1.5 - abs(4.0 * occupancy - 3.0),
        1.5 - abs(4.0 * occupancy - 2.0),
        1.5 - abs(4.0 * occupancy - 1.0)
    ), 0.0, 1.0);
}

vec4 drp_cluster_debug_color(vec3 view_position)
{
    uint cluster_index = drp_cluster_index(view_position);
    uint light_count = cluster_metadata[cluster_index].y;

    // Logarithmic normalization keeps clusters with only a few lights
    // distinguishable when the profile permits much larger lists.
    float capacity = max(cluster_grid.w, 1.0);
    float occupancy = log2(float(light_count) + 1.0) / log2(capacity + 1.0);
    // Keep empty clusters visibly separate from the black clear color. This
    // debug pass colors visible scene surfaces; it does not draw cluster
    // volumes into pixels where there is no geometry.
    vec3 color = light_count == 0u
        ? vec3(0.07, 0.075, 0.085)
        : drp_cluster_heat(clamp(occupancy, 0.0, 1.0));

    // Overflow is deliberately unambiguous rather than part of the heat ramp.
    if (cluster_overflow[cluster_index] != 0u)
    {
        color = vec3(1.0, 0.0, 1.0);
    }

    // Draw fixed screen-tile boundaries over visible geometry.
    vec4 clip = cluster_projection * vec4(view_position, 1.0);
    vec2 ndc = clip.xy / max(abs(clip.w), 0.000001);
    vec2 pixel = (ndc * 0.5 + 0.5) * cluster_screen.xy;
    vec2 cell = mod(pixel, vec2(cluster_screen.z));
    vec2 edge = min(cell, vec2(cluster_screen.z) - cell);
    if (min(edge.x, edge.y) < 1.25)
    {
        color *= 0.18;
    }

    return vec4(color, 1.0);
}

#endif
