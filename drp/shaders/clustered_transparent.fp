#version 430

#include "/drp/shaders/clustered_config.glsl"
#ifdef EDITOR
#define MAX_LIGHT_COUNT 8
#else
#define MAX_LIGHT_COUNT DRP_CLUSTER_LIGHT_CAPACITY
#endif

#include "/drp/shaders/gltf_surface.glsl"
#include "/builtins/materials/gltf_lighting.glsl"
#ifndef EDITOR
#include "/drp/shaders/clustered_pbr.glsl"
#endif
#include "/drp/shaders/output.glsl"

out vec4 out_fragColor;

void main()
{
    PBRMaterial inputs = drp_sample_material(PBR_ALPHA_BLEND);
    // Sample normal maps before discard to preserve derivatives at cutout edges.
    PBRSurface surface = pbr_sample_surface(inputs, var_texcoord0);
    if (drp_should_discard(inputs))
    {
        discard;
    }
#ifndef EDITOR
    if (cluster_debug.x > 0.5)
    {
        out_fragColor = drp_cluster_debug_color(surface.position);
        return;
    }
#endif
    PBRLighting lighting = pbr_create_lighting();
    if (!inputs.unlit)
    {
        MaterialInfo material = pbr_create_material_info(inputs);
#ifdef EDITOR
        lighting.direct = pbr_evaluate_direct_lighting(material, surface, var_view);
#else
        lighting.direct = drp_evaluate_clustered_lighting(material, surface);
#endif
        lighting.indirect = pbr_evaluate_ambient_lighting(material, ambient_light());
    }
    vec3 color = pbr_compose_lighting(inputs, lighting, inputs.occlusion, inputs.occlusion);
    out_fragColor = vec4(drp_output(color), pbr_get_alpha(inputs));
}
