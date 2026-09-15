#version 430

// Alpha-tested depth override. The cutoff matches the visible mask shader so
// cutout geometry does not inflate the tile depth range with solid rectangles.

in mediump mat4 var_view;

#define MAX_LIGHT_COUNT 8

#include "/drp/shaders/cluster_depth_alpha.glsl"
#include "/drp/shaders/cluster_depth_range.glsl"

void main()
{
    if (drp_cluster_base_alpha() < pbrAlphaCutoffAndDoubleSidedAndIsUnlit.x)
    {
        discard;
    }
    drp_record_cluster_depth();
    out_fragColor = vec4(0.0);
}
