#ifndef DRP_SHADOWS_GLSL
#define DRP_SHADOWS_GLSL

// 64 light headers (3 vec4 each), then up to 128 views (6 vec4 each).
// CPU packing is defined by features/shadows/config.lua and shadows.lua.
layout(std430, set = 2, binding = 6) readonly buffer DrpShadowBuffer { vec4 drp_shadow_data[]; };
uniform sampler2D drp_shadow_local;
uniform sampler2D drp_shadow_directional;
uniform fs_drp_shadows {
    mat4 drp_shadow_inverse_view;
    vec4 drp_shadow_settings;
};

float drp_shadow_depth(vec2 uv, bool directional)
{
    if (directional) return texture(drp_shadow_directional, uv).r;
    return texture(drp_shadow_local, uv).r;
}
vec2 drp_shadow_tap(int tap, int count)
{
    // Fixed disk pattern, no temporal noise or per-frame rotation.
    float angle = float(tap) * 2.39996323;
    return vec2(cos(angle), sin(angle)) * sqrt((float(tap) + 0.5) / float(count));
}
float drp_shadow_linear_depth(float depth, vec2 planes, bool directional)
{
    if (directional) return mix(planes.x, planes.y, depth);
    return (planes.x * planes.y) / max(planes.y - depth * (planes.y - planes.x), 0.00001);
}
float drp_shadow_view(uint view_index, vec3 world, vec4 settings, float softness, bool directional)
{
    uint base = 192u + view_index * 6u;
    mat4 matrix = mat4(drp_shadow_data[base], drp_shadow_data[base + 1u],
        drp_shadow_data[base + 2u], drp_shadow_data[base + 3u]);
    vec4 rect = drp_shadow_data[base + 4u];
    vec2 planes = drp_shadow_data[base + 5u].xy;
    vec4 clip = matrix * vec4(world, 1.0);
    if (clip.w <= 0.0) return 1.0;
    vec3 coord = clip.xyz / clip.w * 0.5 + 0.5;
    if (any(lessThan(coord, vec3(0.0))) || any(greaterThan(coord, vec3(1.0)))) return 1.0;
    vec2 uv = rect.xy + coord.xy * rect.z;
    vec2 minimum_uv = rect.xy + vec2(rect.w * 0.5);
    vec2 maximum_uv = rect.xy + vec2(rect.z - rect.w * 0.5);
    float receiver = coord.z - settings.x;
    if (settings.w < 1.5 || softness <= 0.0)
        return step(receiver, drp_shadow_depth(clamp(uv, minimum_uv, maximum_uv), directional));
    float radius = softness;
    if (settings.w >= 2.5)
    {
        float blockers = 0.0;
        float blocker_distance = 0.0;
        for (int i = 0; i < 8; ++i)
        {
            float depth = drp_shadow_depth(clamp(uv + drp_shadow_tap(i, 8) * softness * rect.w,
                minimum_uv, maximum_uv), directional);
            if (depth < receiver)
            {
                blocker_distance += drp_shadow_linear_depth(depth, planes, directional);
                blockers += 1.0;
            }
        }
        if (blockers == 0.0) return 1.0;
        float average = blocker_distance / blockers;
        float distance = drp_shadow_linear_depth(coord.z, planes, directional);
        // Bounded PCSS approximation: a fixed maximum search/filter radius in texels.
        radius = clamp(softness * (distance - average) / max(average, 0.001), min(0.5, softness), softness);
    }
    int count = settings.w >= 3.5 ? 32 : 16;
    float visibility = 0.0;
    for (int i = 0; i < 32; ++i)
    {
        if (i >= count) break;
        vec2 tap_uv = clamp(uv + drp_shadow_tap(i, count) * radius * rect.w, minimum_uv, maximum_uv);
        visibility += step(receiver, drp_shadow_depth(tap_uv, directional));
    }
    return visibility / float(count);
}
uint drp_shadow_point_face(vec3 direction)
{
    vec3 magnitude = abs(direction);
    if (magnitude.x >= magnitude.y && magnitude.x >= magnitude.z) return direction.x >= 0.0 ? 0u : 1u;
    if (magnitude.y >= magnitude.z) return direction.y >= 0.0 ? 2u : 3u;
    return direction.z >= 0.0 ? 4u : 5u;
}
float drp_shadow_visibility(uint light_index, vec3 view_position, vec3 view_normal, vec3 light_position)
{
    if (drp_shadow_settings.x < 0.5 || light_index >= 64u) return 1.0;
    vec4 light = drp_shadow_data[light_index * 3u];
    if (light.z < 0.5) return 1.0;
    vec4 settings = drp_shadow_data[light_index * 3u + 1u];
    vec3 world = (drp_shadow_inverse_view * vec4(view_position, 1.0)).xyz;
    vec3 normal = normalize(mat3(drp_shadow_inverse_view) * view_normal);
    world += normal * settings.y;
    uint first = uint(light.y);
    if (light.x < 0.5)
    {
        vec4 splits = drp_shadow_data[light_index * 3u + 2u];
        float depth = -view_position.z;
        int count = int(light.z);
        int cascade = 0;
        for (int i = 0; i < 4; ++i)
        {
            if (i >= count - 1 || depth <= splits[i]) break;
            cascade += 1;
        }
        if (depth > splits[count - 1]) return 1.0;
        float visibility = drp_shadow_view(first + uint(cascade), world, settings, light.w, true);
        float previous = cascade == 0 ? 0.0 : splits[cascade - 1];
        float blend_start = splits[cascade] - (splits[cascade] - previous) * settings.z;
        if (settings.z > 0.0 && depth > blend_start)
        {
            float next = cascade + 1 < count ? drp_shadow_view(first + uint(cascade + 1), world, settings, light.w, true) : 1.0;
            visibility = mix(visibility, next, smoothstep(blend_start, splits[cascade], depth));
        }
        return visibility;
    }
    uint face = light.x < 1.5 ? drp_shadow_point_face(world - light_position) : 0u;
    return drp_shadow_view(first + face, world, settings, light.w, false);
}
#endif
