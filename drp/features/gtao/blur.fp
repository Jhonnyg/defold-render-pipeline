#version 140

in vec2 var_texcoord0;
out vec4 out_fragColor;

uniform sampler2D drp_scene_depth;
uniform sampler2D drp_gtao_raw;
uniform fs_drp_gtao_blur
{
    // xy: full-resolution depth/output size, zw: reciprocal depth size.
    vec4 gtao_depth_size;
    // xy: raw AO size, zw: reciprocal raw AO size.
    vec4 gtao_target_size;
    // x: AO radius in world units, y: depth rejection strength, zw: reserved.
    vec4 gtao_filter_settings;
};

float gtao_depth(vec2 uv)
{
    vec2 pixel = clamp(floor(uv * gtao_depth_size.xy),
        vec2(0.0), gtao_depth_size.xy - vec2(1.0));
    return textureLod(drp_scene_depth, (pixel + vec2(0.5)) * gtao_depth_size.zw, 0.0).r;
}

void main()
{
#ifdef EDITOR
    out_fragColor = vec4(1.0);
#else
    float center_depth = gtao_depth(var_texcoord0);
    if (center_depth <= 0.0)
    {
        out_fragColor = vec4(1.0);
        return;
    }

    vec2 center_pixel = floor(var_texcoord0 * gtao_target_size.xy);
    float visibility_sum = 0.0;
    float weight_sum = 0.0;
    for (int y = -2; y <= 2; ++y)
    {
        for (int x = -2; x <= 2; ++x)
        {
            vec2 pixel = center_pixel + vec2(float(x), float(y));
            if (any(lessThan(pixel, vec2(0.0)))
                || any(greaterThanEqual(pixel, gtao_target_size.xy)))
            {
                continue;
            }

            // Sample the actual raw texel center, then the same full-resolution
            // depth representative used by GTAO. This matters at half resolution.
            vec2 uv = (pixel + vec2(0.5)) * gtao_target_size.zw;
            float depth = gtao_depth(uv);
            float relative_delta = abs(depth - center_depth) / max(gtao_filter_settings.x, 0.0001);
            if (depth <= 0.0 || relative_delta > 0.5)
            {
                continue;
            }

            vec2 offset = (uv - var_texcoord0) * gtao_target_size.xy;
            float spatial_weight = exp(-0.25 * dot(offset, offset));
            float depth_weight = exp(-relative_delta * gtao_filter_settings.y);
            float weight = spatial_weight * depth_weight;
            visibility_sum += textureLod(drp_gtao_raw, uv, 0.0).r * weight;
            weight_sum += weight;
        }
    }

    // Thin geometry that had no representative raw sample stays unoccluded;
    // borrowing a different surface's AO would create a dark silhouette halo.
    float visibility = weight_sum > 0.000001 ? visibility_sum / weight_sum : 1.0;
    out_fragColor = vec4(vec3(visibility), 1.0);
#endif
}
