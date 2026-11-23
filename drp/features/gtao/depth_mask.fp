#version 140

#include "/drp/shaders/gltf_surface.glsl"

out vec4 out_fragColor;

void main()
{
    // Match visible glTF alpha coverage, vertex color and sidedness.
    PBRMaterial inputs = drp_sample_material(PBR_ALPHA_MASK);
    if (drp_should_discard(inputs))
    {
        discard;
    }

    // Positive linear view depth in R32F. A zero clear value denotes background.
    out_fragColor = vec4(max(-var_position.z, 0.0), 0.0, 0.0, 1.0);
}
