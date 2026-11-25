#ifndef DRP_AMBIENT_OCCLUSION_GLSL
#define DRP_AMBIENT_OCCLUSION_GLSL

#ifndef EDITOR
uniform sampler2D drp_ao_texture;
uniform fs_drp_ao
{
    mat4 drp_ao_projection;
    // x: current-frame AO is ready; yz: inverse full-resolution target size;
    // w: reserved. Disabled frames return unoccluded without sampling a target.
    vec4 drp_ao_settings;
};
#endif

float drp_ambient_visibility(vec3 view_position)
{
#ifdef EDITOR
    return 1.0;
#else
    if (drp_ao_settings.x < 0.5)
    {
        return 1.0;
    }

    // Use the camera's projection-space UVs, matching the depth prepass and
    // fullscreen passes on every backend, independently of gl_FragCoord origin.
    vec4 clip = drp_ao_projection * vec4(view_position, 1.0);
    vec2 uv = clip.xy / max(abs(clip.w), 0.000001) * 0.5 + 0.5;
    vec2 inset = drp_ao_settings.yz * 0.5;
    return textureLod(drp_ao_texture, clamp(uv, inset, vec2(1.0) - inset), 0.0).r;
#endif
}

#endif
