#version 430

// Diagnostic fragment shader for isolating the clustered graphics program.
// This stage adds only the three read-only cluster SSBOs used by clustered
// fragment shading, the clustered fragment UBO, and the engine-owned
// LightBuffer. It deliberately has no samplers or PBR material resources. The
// stock asset-pbr vertex shader still exercises the model transform and
// normal-matrix inputs.

in mediump vec3 var_normal;

out vec4 out_fragColor;

layout(std430, set = 2, binding = 2) readonly buffer ClusterMetadataBuffer
{
    uvec2 cluster_metadata[];
};

layout(std430, set = 2, binding = 3) readonly buffer ClusterLightIndicesBuffer
{
    uint cluster_light_indices[];
};

layout(std430, set = 2, binding = 5) readonly buffer ClusterOverflowBuffer
{
    uint cluster_overflow[];
};

uniform fs_drp_clustered
{
    mat4 cluster_projection;
    vec4 cluster_grid;
    vec4 cluster_screen;
    vec4 cluster_z_params;
    vec4 cluster_debug;
};

// Deliberately use a non-reserved, flat block for this stage. This keeps an
// additional fragment UBO at the same descriptor location while removing the
// nested struct type from reflection.
layout(std140, set = 3, binding = 0) uniform ProbeLightBuffer
{
    vec4 light_info;
    vec4 light_probe[4];
};

void main()
{
    // Read a known-valid cluster entry so all three bindings remain in shader
    // reflection. The light-index read is guarded by the corresponding count.
    uvec2 metadata = cluster_metadata[0];
    uint probe = metadata.x ^ metadata.y ^ cluster_overflow[0];
    if (metadata.y > 0u)
    {
        probe ^= cluster_light_indices[metadata.x];
    }

    vec3 normal_color = normalize(var_normal) * 0.5 + 0.5;
    // Touch every UBO member while keeping its visual contribution tiny.
    float uniform_probe = cluster_projection[0][0] + cluster_grid.x +
        cluster_screen.x + cluster_z_params.x + cluster_debug.x;
    float marker = float(probe & 1u) * 0.03 +
        float(uniform_probe < -1.0e20) * 0.03;

    // Keep both the LightBuffer header and array reflected, but do not feed
    // ordinary light values into the visible colour. A broken binding can
    // contain very large values or NaNs, which would otherwise make a healthy
    // normal visualization look flat through saturation alone.
    float light_marker = float(light_info.w < 0.0 || light_info.w > 1.0) * 0.03;
    if (light_info.w > 0.0)
    {
        light_marker += float(light_probe[3].y < -1.0e20) * 0.03;
    }
    out_fragColor = vec4(normal_color + marker + light_marker, 1.0);
}
