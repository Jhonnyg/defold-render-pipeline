#version 140

#include "/drp/shaders/gltf_surface.glsl"

out vec4 out_fragColor;

void main()
{
    PBRMaterial inputs = drp_sample_material(PBR_ALPHA_MASK);
    if (drp_should_discard(inputs))
    {
        discard;
    }
    out_fragColor = vec4(gl_FragCoord.z);
}
