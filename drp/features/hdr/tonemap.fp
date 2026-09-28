#version 140
in vec2 var_texcoord0;
out vec4 out_fragColor;
uniform sampler2D texture0;
uniform fs_tonemap_uniforms
{
    // x: manual exposure in stops (EV).
    vec4 hdr_settings;
};

#include "/drp/features/hdr/tonemap.glsl"

void main()
{
#ifdef EDITOR
    discard;
#else
    vec3 scene = texture(texture0, var_texcoord0).rgb;
    out_fragColor = vec4(drp_tonemap(scene, hdr_settings.x), 1.0);
#endif
}
