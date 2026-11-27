#version 140
in vec2 var_texcoord0;
out vec4 out_fragColor;
uniform sampler2D drp_debug_texture;
uniform fs_debug_uniforms
{
    // x: 0 = AO visibility, 1 = logarithmic positive view-space depth.
    // y: camera far plane for depth normalization. z/w: reserved.
    vec4 drp_debug_settings;
};

void main()
{
#ifdef EDITOR
    discard;
#else
    float value = texture(drp_debug_texture, var_texcoord0).r;
    if (drp_debug_settings.x > 0.5)
    {
        // Cleared depth is zero (no geometry). Keep it black; positive depths
        // grow brighter with distance. Logarithmic scaling reveals nearby detail.
        value = value > 0.0
            ? log(1.0 + value) / log(1.0 + max(drp_debug_settings.y, 0.001))
            : 0.0;
    }

    // Debug values are displayed directly, without exposure or display gamma.
    // AO is white when unoccluded and dark where geometry blocks ambient light.
    out_fragColor = vec4(vec3(clamp(value, 0.0, 1.0)), 1.0);
#endif
}
