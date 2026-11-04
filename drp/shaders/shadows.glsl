#ifndef DRP_SHADOWS_GLSL
#define DRP_SHADOWS_GLSL

const uint DRP_SHADOW_LIGHT_CAPACITY = 64u;

// std430: 48 bytes per light. All scalar fields are floats because the CPU
// uploads them with native.pack_floats(), including the integer-valued fields.
struct DrpShadowLight
{
    float light_type;       // 0 = directional, 1 = point, 2 = spot.
    float first_view;       // Zero-based index into drp_shadow_views.
    float view_count;       // 0 = no valid shadow map; otherwise 1 spot, 6 point, 1-4 cascades.
    float softness;         // Maximum search/filter radius in atlas texels.
    float depth_bias;       // Bias subtracted from the receiver's normalized depth.
    float normal_bias;      // World-space offset along the receiver's normal.
    float cascade_blend;    // Fraction of each cascade depth interval used for blending.
    float filter_mode;      // 1 = hard, 2 = PCF, 3 = PCSS, 4 = PCSS with 32 filter taps.
    vec4  cascade_splits;   // Positive camera-space far depth for each directional cascade.
};

// std430: 96 bytes per view. A view is one spot projection, point-light cube
// face, or directional cascade. Depth samples live in the atlas textures.
struct DrpShadowView
{
    mat4  world_to_clip;    // Column-major light projection * view matrix.
    vec2  atlas_offset;     // Normalized origin of the tile interior, excluding its border.
    float atlas_scale;      // Normalized width/height of the square tile interior.
    float atlas_texel_size; // Reciprocal atlas texture size.
    float near_plane;       // Positive light-space clip distances for depth linearization.
    float far_plane;
    float shadow_distance;  // Configured shadow distance; currently unused by the receiver.
    float padding;          // Reserved, written as zero.
};

// Metadata only: headers share the engine's compact light-buffer indices;
// each header points into the densely packed views that have valid atlas maps.
// Lua allocates 64 * 48 + 128 * 96 = 15360 bytes. Keep this std430 layout in
// sync with features/shadows/config.lua and shadows.lua::publish().
layout(std430, set = 2, binding = 6) readonly buffer DrpShadowBuffer
{
    DrpShadowLight drp_shadow_lights[DRP_SHADOW_LIGHT_CAPACITY];
    DrpShadowView  drp_shadow_views[];
};

uniform sampler2D drp_shadow_local;
uniform sampler2D drp_shadow_directional;

uniform fs_drp_shadows
{
    // x: 1 when shadow resources/metadata are available for this scene pass,
    //    0 to bypass shadow sampling (individual lights still use view_count).
    // yzw: reserved, written as zero by shadows.lua::bind_scene().
    vec4 drp_shadow_settings;
};

float drp_shadow_depth(vec2 uv, bool directional)
{
    if (directional)
    {
        return texture(drp_shadow_directional, uv).r;
    }
    return texture(drp_shadow_local, uv).r;
}

vec2 drp_shadow_tap(int tap, int count)
{
    // Fixed disk pattern, no temporal noise or per-frame rotation.
    float angle = float(tap) * 2.39996323;
    return vec2(cos(angle), sin(angle)) * sqrt((float(tap) + 0.5) / float(count));
}

float drp_shadow_linear_depth(float depth, DrpShadowView view, bool directional)
{
    if (directional)
    {
        return mix(view.near_plane, view.far_plane, depth);
    }
    return (view.near_plane * view.far_plane)
        / max(view.far_plane - depth * (view.far_plane - view.near_plane), 0.00001);
}

float drp_shadow_view(uint view_index, vec3 world, DrpShadowLight light, bool directional)
{
    DrpShadowView view = drp_shadow_views[view_index];

    vec4 clip = view.world_to_clip * vec4(world, 1.0);
    if (clip.w <= 0.0)
    {
        return 1.0;
    }

    vec3 coord = clip.xyz / clip.w * 0.5 + 0.5;
    if (any(lessThan(coord, vec3(0.0))) || any(greaterThan(coord, vec3(1.0))))
    {
        return 1.0;
    }

    // Clamp every tap to this tile so adjacent lights cannot bleed into it.
    vec2 uv = view.atlas_offset + coord.xy * view.atlas_scale;
    vec2 minimum_uv = view.atlas_offset + vec2(view.atlas_texel_size * 0.5);
    vec2 maximum_uv = view.atlas_offset + vec2(view.atlas_scale - view.atlas_texel_size * 0.5);
    float receiver = coord.z - light.depth_bias;
    if (light.filter_mode < 1.5 || light.softness <= 0.0)
    {
        return step(receiver, drp_shadow_depth(clamp(uv, minimum_uv, maximum_uv), directional));
    }

    // PCSS estimates blocker distance before the bounded PCF filter below.
    float radius = light.softness;
    if (light.filter_mode >= 2.5)
    {
        float blockers = 0.0;
        float blocker_distance = 0.0;
        for (int i = 0; i < 8; ++i)
        {
            float depth = drp_shadow_depth(clamp(uv + drp_shadow_tap(i, 8) * light.softness * view.atlas_texel_size,
                                                 minimum_uv, maximum_uv), directional);
            if (depth < receiver)
            {
                blocker_distance += drp_shadow_linear_depth(depth, view, directional);
                blockers += 1.0;
            }
        }

        if (blockers == 0.0)
        {
            return 1.0;
        }

        float average = blocker_distance / blockers;
        float distance = drp_shadow_linear_depth(coord.z, view, directional);
        // Bounded PCSS approximation: a fixed maximum search/filter radius in texels.
        radius = clamp(light.softness * (distance - average) / max(average, 0.001),
                       min(0.5, light.softness), light.softness);
    }

    int count = light.filter_mode >= 3.5 ? 32 : 16;
    float visibility = 0.0;
    for (int i = 0; i < 32; ++i)
    {
        if (i >= count)
        {
            break;
        }
        vec2 tap_uv = clamp(uv + drp_shadow_tap(i, count) * radius * view.atlas_texel_size, minimum_uv, maximum_uv);
        visibility += step(receiver, drp_shadow_depth(tap_uv, directional));
    }
    return visibility / float(count);
}

uint drp_shadow_point_face(vec3 direction)
{
    vec3 magnitude = abs(direction);
    if (magnitude.x >= magnitude.y && magnitude.x >= magnitude.z)
    {
        return direction.x >= 0.0 ? 0u : 1u;
    }
    if (magnitude.y >= magnitude.z)
    {
        return direction.y >= 0.0 ? 2u : 3u;
    }
    return direction.z >= 0.0 ? 4u : 5u;
}

float drp_shadow_visibility(uint light_index, PBRSurface surface, vec3 light_position)
{
    if (drp_shadow_settings.x < 0.5 || light_index >= DRP_SHADOW_LIGHT_CAPACITY)
    {
        return 1.0;
    }

    // A zero view count means this light has no valid map for the current frame.
    DrpShadowLight light = drp_shadow_lights[light_index];
    if (light.view_count < 0.5)
    {
        return 1.0;
    }

    vec3 world = surface.worldPosition + surface.worldNormal * light.normal_bias;
    uint first = uint(light.first_view);

    // Directional lights select a cascade by positive camera-space depth.
    if (light.light_type < 0.5)
    {
        vec4 splits = light.cascade_splits;
        float depth = -surface.position.z;
        int count = int(light.view_count);
        int cascade = 0;
        for (int i = 0; i < 4; ++i)
        {
            if (i >= count - 1 || depth <= splits[i])
            {
                break;
            }
            cascade += 1;
        }
        if (depth > splits[count - 1])
        {
            return 1.0;
        }

        // Blend through the overlap, fading the final cascade into full light.
        float visibility = drp_shadow_view(first + uint(cascade), world, light, true);
        float previous = cascade == 0 ? 0.0 : splits[cascade - 1];
        float blend_start = splits[cascade] - (splits[cascade] - previous) * light.cascade_blend;
        if (light.cascade_blend > 0.0 && depth > blend_start)
        {
            float next = cascade + 1 < count
                ? drp_shadow_view(first + uint(cascade + 1), world, light, true)
                : 1.0;
            visibility = mix(visibility, next, smoothstep(blend_start, splits[cascade], depth));
        }
        return visibility;
    }

    // Point lights choose a cube face; a spot light has one view.
    uint face = light.light_type < 1.5 ? drp_shadow_point_face(world - light_position) : 0u;
    return drp_shadow_view(first + face, world, light, false);
}
#endif
