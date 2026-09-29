#ifndef DRP_OUTPUT_GLSL
#define DRP_OUTPUT_GLSL

uniform fs_drp_output
{
    // x: write linear scene color into the HDR target.
    vec4 drp_output_settings;
};

vec3 drp_output(vec3 linear_color)
{
#ifdef EDITOR
    return to_output(linear_color);
#else
    return drp_output_settings.x > 0.5 ? linear_color : to_output(linear_color);
#endif
}

#endif
