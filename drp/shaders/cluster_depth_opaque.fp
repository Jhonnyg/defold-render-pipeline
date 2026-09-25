#version 430

// Depth-only override for clustered opaque geometry. Color writes are disabled
// by the render script; the fragment shader records the visible tile range.

layout(location = 0) out vec4 out_fragColor;

#include "/drp/shaders/cluster_depth_range.glsl"

void main()
{
    drp_record_cluster_depth();
    out_fragColor = vec4(0.0);
}
