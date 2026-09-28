#ifndef DRP_TONEMAP_GLSL
#define DRP_TONEMAP_GLSL

// Ported from the POC's HDR resolve. This is the inexpensive ACES-style
// fitted curve, not the full ACES color-management pipeline.
vec3 drp_aces_fitted(vec3 color)
{
    // Above this value the curve already saturates. Clamping before its
    // quadratic terms also avoids overflow for half-float HDR highlights.
    color = clamp(color, vec3(0.0), vec3(64.0));
    return clamp((color * (2.51 * color + 0.03)) /
        (color * (2.43 * color + 0.59) + 0.14), 0.0, 1.0);
}

vec3 drp_linear_to_srgb(vec3 color)
{
    vec3 low = color * 12.92;
    vec3 high = 1.055 * pow(max(color, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
    return mix(high, low, lessThanEqual(color, vec3(0.0031308)));
}

vec3 drp_tonemap(vec3 color, float exposure)
{
    return drp_linear_to_srgb(drp_aces_fitted(max(color, vec3(0.0)) * exp2(exposure)));
}

#endif
