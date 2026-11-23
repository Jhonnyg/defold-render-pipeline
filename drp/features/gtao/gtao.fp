#version 140

in vec2 var_texcoord0;
out vec4 out_fragColor;

uniform sampler2D drp_scene_depth;
uniform fs_drp_gtao
{
    mat4 gtao_inverse_projection;
    mat4 gtao_projection;
    // xy: full-resolution depth size, zw: reciprocal depth size.
    vec4 gtao_depth_size;
    // xy: AO evaluation size, zw: reciprocal AO evaluation size.
    vec4 gtao_target_size;
    // x: world-space radius, y: intensity, z: visibility power,
    // w: horizon-cosine bias to suppress depth reconstruction self-occlusion.
    vec4 gtao_settings;
    // x: slice count (1..6), y: steps per side (1..8),
    // z: falloff start as a fraction of radius, w: maximum radius in pixels.
    vec4 gtao_quality;
};

const float DRP_GTAO_PI = 3.14159265359;
const float DRP_GTAO_HALF_PI = 1.57079632679;
const float DRP_GTAO_EPSILON = 0.000001;

vec2 gtao_depth_uv(vec2 uv)
{
    // Reduced-resolution centers can fall between full-resolution texels.
    // Always choose the same explicit depth texel for evaluation and filtering.
    vec2 pixel = clamp(floor(uv * gtao_depth_size.xy),
        vec2(0.0), gtao_depth_size.xy - vec2(1.0));
    return (pixel + vec2(0.5)) * gtao_depth_size.zw;
}

bool gtao_inside(vec2 uv)
{
    return all(greaterThanEqual(uv, vec2(0.0)))
        && all(lessThan(uv, vec2(1.0)));
}

float gtao_depth(vec2 uv)
{
    // Explicit LOD remains valid after data-dependent branches on WebGPU.
    return textureLod(drp_scene_depth, gtao_depth_uv(uv), 0.0).r;
}

vec3 gtao_position(vec2 uv, float depth)
{
    // Solve homogeneous unprojection for a known view-space Z. Unlike a
    // symmetric-frustum shortcut, this also handles off-center and orthographic
    // cameras and does not depend on the hardware depth range.
    vec4 origin = gtao_inverse_projection * vec4(uv * 2.0 - 1.0, 0.0, 1.0);
    vec4 axis = gtao_inverse_projection[2];
    // Cancel the clip-Z denominator algebraically before dividing. Computing
    // clip Z first would lose precision as perspective depth approaches far Z.
    float depth_axis = axis.z + depth * axis.w;
    float clip_offset = -depth * origin.w - origin.z;
    vec4 position = origin * depth_axis + axis * clip_offset;
    float divisor = origin.w * axis.z - origin.z * axis.w;
    return vec3(position.x / divisor, position.y / divisor, -depth);
}

vec3 gtao_view_direction(vec3 position)
{
    if (abs(gtao_projection[3][3]) > 0.5)
    {
        return vec3(0.0, 0.0, 1.0);
    }
    return normalize(-position);
}

vec3 gtao_axis_delta(vec2 uv, vec2 offset, vec3 center)
{
    vec2 negative_uv = uv - offset;
    vec2 positive_uv = uv + offset;
    float negative_depth = gtao_inside(negative_uv) ? gtao_depth(negative_uv) : 0.0;
    float positive_depth = gtao_inside(positive_uv) ? gtao_depth(positive_uv) : 0.0;

    // Unproject only positive depths: zero is a sentinel, not a point on the
    // camera plane (whose homogeneous representation can be singular).
    vec3 negative_delta = center - gtao_position(negative_uv,
        negative_depth > 0.0 ? negative_depth : -center.z);
    vec3 positive_delta = gtao_position(positive_uv,
        positive_depth > 0.0 ? positive_depth : -center.z) - center;
    if (negative_depth > 0.0 && (positive_depth <= 0.0
        || abs(negative_delta.z) < abs(positive_delta.z)))
    {
        return negative_delta;
    }
    if (positive_depth > 0.0)
    {
        return positive_delta;
    }

    // Isolated pixels have no usable derivative. A same-depth neighbor gives
    // a finite camera-facing fallback instead of propagating a zero normal.
    return gtao_position(uv + offset, -center.z) - center;
}

vec3 gtao_normal(vec2 uv, vec3 position, vec3 view_direction)
{
    // Prefer the nearer depth difference on each axis to avoid forming a
    // normal across a foreground/background discontinuity.
    vec3 dx = gtao_axis_delta(uv, vec2(gtao_depth_size.z, 0.0), position);
    vec3 dy = gtao_axis_delta(uv, vec2(0.0, gtao_depth_size.w), position);
    vec3 normal = cross(dx, dy);
    float normal_length = length(normal);
    if (normal_length <= DRP_GTAO_EPSILON * DRP_GTAO_EPSILON)
    {
        return view_direction;
    }
    normal /= normal_length;
    return dot(normal, view_direction) < 0.0 ? -normal : normal;
}

float gtao_noise(vec2 pixel)
{
    // Screen-stable rotation: this first version has no temporal history.
    return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

float gtao_arc(float angle, float normal_angle)
{
    // Analytic integral of cos(theta - normal_angle) * abs(sin(theta)).
    // Sum this primitive at the signed negative and positive horizon angles.
    // Jimenez et al., GTAO, section 4.1, equations 7-9:
    // https://www.activision.com/cdn/research/Practical_Real_Time_Strategies_for_Accurate_Indirect_Occlusion_NEW%20VERSION_COLOR.pdf
    return 0.25 * (cos(normal_angle) - cos(2.0 * angle - normal_angle)
        + 2.0 * angle * sin(normal_angle));
}

float gtao_horizon(vec2 uv, vec3 center, vec3 view_direction,
    vec2 direction, float radius_pixels, float tangent_cosine, float jitter)
{
    float horizon_cosine = tangent_cosine;
    float radius = gtao_settings.x;
    int step_count = int(clamp(gtao_quality.y, 1.0, 8.0));
    for (int step_index = 0; step_index < 8; ++step_index)
    {
        if (step_index >= step_count)
        {
            break;
        }

        // Quadratic spacing spends more samples near contact creases while
        // covering the radius. One pixel is the smallest useful depth offset.
        float fraction = (float(step_index) + 0.5 + jitter * 0.5) / float(step_count);
        float pixel_distance = max(1.0, fraction * fraction * radius_pixels);
        vec2 sample_uv = uv + direction * pixel_distance * gtao_depth_size.zw;
        if (!gtao_inside(sample_uv))
        {
            continue;
        }
        sample_uv = gtao_depth_uv(sample_uv);
        float sample_depth = gtao_depth(sample_uv);
        if (sample_depth <= 0.0)
        {
            continue;
        }

        vec3 delta = gtao_position(sample_uv, sample_depth) - center;
        float distance_to_sample = length(delta);
        if (distance_to_sample <= DRP_GTAO_EPSILON)
        {
            continue;
        }

        float falloff_start = radius * clamp(gtao_quality.z, 0.0, 0.99);
        float weight = 1.0 - smoothstep(falloff_start, radius, distance_to_sample);
        float sample_cosine = dot(delta / distance_to_sample, view_direction)
            - gtao_settings.w;
        // Fade toward the surface tangent, keeping distant samples neutral
        // even when the surface normal is strongly tilted toward the camera.
        horizon_cosine = max(horizon_cosine,
            mix(tangent_cosine, sample_cosine, weight));
    }
    return clamp(horizon_cosine, -1.0, 1.0);
}

void main()
{
#ifdef EDITOR
    out_fragColor = vec4(1.0);
#else
    vec2 uv = gtao_depth_uv(var_texcoord0);
    float depth = gtao_depth(uv);
    if (depth <= 0.0)
    {
        out_fragColor = vec4(1.0);
        return;
    }

    vec3 position = gtao_position(uv, depth);
    vec3 view_direction = gtao_view_direction(position);
    vec3 normal = gtao_normal(uv, position, view_direction);
    int slice_count = int(clamp(gtao_quality.x, 1.0, 6.0));
    float noise = gtao_noise(floor(var_texcoord0 * gtao_target_size.xy));
    float visible_integral = 0.0;
    float unoccluded_integral = 0.0;

    for (int slice_index = 0; slice_index < 6; ++slice_index)
    {
        if (slice_index >= slice_count)
        {
            break;
        }

        float angle = (float(slice_index) + noise) * DRP_GTAO_PI / float(slice_count);
        vec2 direction = vec2(cos(angle), sin(angle));
        vec3 pixel_delta = gtao_position(uv + direction * gtao_depth_size.zw, depth) - position;
        float radius_pixels = min(gtao_settings.x / max(length(pixel_delta), DRP_GTAO_EPSILON),
            gtao_quality.w);

        // A slice contains the view ray and this screen direction. Project
        // the normal into it before integrating the cosine-weighted arc.
        vec3 tangent = normalize(pixel_delta - view_direction * dot(pixel_delta, view_direction));
        float normal_view = max(dot(normal, view_direction), 0.0);
        float normal_tangent = dot(normal, tangent);
        float projected_length = length(vec2(normal_view, normal_tangent));
        if (projected_length <= DRP_GTAO_EPSILON)
        {
            continue;
        }

        float normal_angle = atan(normal_tangent, normal_view);
        float negative_tangent = normal_angle - DRP_GTAO_HALF_PI;
        float positive_tangent = normal_angle + DRP_GTAO_HALF_PI;
        float baseline = projected_length * (gtao_arc(negative_tangent, normal_angle)
            + gtao_arc(positive_tangent, normal_angle));
        unoccluded_integral += baseline;

        if (radius_pixels < 1.0)
        {
            visible_integral += baseline;
            continue;
        }

        float jitter = fract(noise + float(slice_index) * 0.61803398875);
        float negative_cosine = gtao_horizon(uv, position, view_direction,
            -direction, radius_pixels, cos(negative_tangent), jitter);
        float positive_cosine = gtao_horizon(uv, position, view_direction,
            direction, radius_pixels, cos(positive_tangent), jitter);
        float negative_angle = max(-acos(negative_cosine), negative_tangent);
        float positive_angle = min(acos(positive_cosine), positive_tangent);
        visible_integral += projected_length * (gtao_arc(negative_angle, normal_angle)
            + gtao_arc(positive_angle, normal_angle));
    }

    // The same finite slice set integrates the unoccluded hemisphere. Dividing
    // by it keeps flat planes white even with low slice counts and oblique views.
    float visibility = clamp(visible_integral / max(unoccluded_integral, DRP_GTAO_EPSILON), 0.0, 1.0);
    visibility = pow(clamp(1.0 - (1.0 - visibility) * gtao_settings.y, 0.0, 1.0),
        max(gtao_settings.z, 0.01));
    out_fragColor = vec4(vec3(visibility), 1.0);
#endif
}
