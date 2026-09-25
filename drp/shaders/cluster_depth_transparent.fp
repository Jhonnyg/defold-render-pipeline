#version 430

// Transparent objects contribute to tile depth ranges without updating the
// opaque hardware depth buffer. This keeps every visible transparent layer's
// cluster active while still allowing empty depth slices to be rejected.

in mediump mat4 var_view;

#define MAX_LIGHT_COUNT 8

#include "/drp/shaders/cluster_depth_alpha.glsl"
#include "/drp/shaders/cluster_depth_range.glsl"

void main()
{
    if (drp_cluster_base_alpha() <= 0.001)
    {
        discard;
    }
    drp_record_cluster_depth();
    out_fragColor = vec4(0.0);
}
