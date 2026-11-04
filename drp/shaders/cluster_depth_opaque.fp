#version 430

// Coverage and sidedness must match the visible pass. Unused glTF texture
// samples are eliminated; depth only needs base alpha and material flags.
#include "/drp/shaders/gltf_surface.glsl"
#include "/drp/shaders/cluster_depth_range.glsl"

out vec4 out_fragColor;

void main()
{
    PBRMaterial inputs = drp_sample_material(PBR_ALPHA_OPAQUE);
    if (drp_should_discard(inputs))
    {
        discard;
    }
    drp_record_cluster_depth();
    out_fragColor = vec4(0.0);
}
