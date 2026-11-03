#version 140
in mediump mat4 var_view;
#define MAX_LIGHT_COUNT 8
#include "/drp/shaders/cluster_depth_alpha.glsl"
void main()
{
    if (drp_cluster_base_alpha() < pbrAlphaCutoffAndDoubleSidedAndIsUnlit.x) discard;
    out_fragColor = vec4(gl_FragCoord.z);
}
