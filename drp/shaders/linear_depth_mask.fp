#version 430

// Writes positive linear view-space depth for alpha-masked clustered geometry.
// It repeats the base-color alpha test from clustered_mask.fp so holes in
// foliage and other cutouts do not incorrectly occlude the depth prepass.

in highp vec4 var_position;
in mediump vec2 var_texcoord0;
layout(location = 0) out vec4 out_fragColor;

uniform sampler2D PbrMetallicRoughness_baseColorTexture;

struct PbrMetallicRoughness
{
    vec4 baseColorFactor;
    vec4 metallicAndRoughnessFactor;
    vec4 metallicRoughnessTextures;
};

uniform PbrMaterial
{
    vec4 pbrAlphaCutoffAndDoubleSidedAndIsUnlit;
    vec4 pbrCommonTextures;
    PbrMetallicRoughness pbrMetallicRoughness;
};

void main()
{
    // The model pipeline encodes texture presence in the material flag vector.
    vec4 base_color = pbrMetallicRoughness.baseColorFactor;
    if (pbrMetallicRoughness.metallicRoughnessTextures.x > 0.5)
    {
        base_color *= texture(PbrMetallicRoughness_baseColorTexture, var_texcoord0);
    }
    if (base_color.a < pbrAlphaCutoffAndDoubleSidedAndIsUnlit.x)
    {
        discard;
    }
    // Camera-forward positions have negative view-space Z in Defold.
    out_fragColor = vec4(vec3(max(-var_position.z, 0.0)), 1.0);
}
