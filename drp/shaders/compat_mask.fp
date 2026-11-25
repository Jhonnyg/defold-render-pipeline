#version 140

#define MAX_LIGHT_COUNT 8

#include "/drp/shaders/gltf_surface.glsl"
#include "/builtins/materials/gltf_lighting.glsl"
#include "/drp/shaders/output.glsl"
#include "/drp/shaders/ambient_occlusion.glsl"

out vec4 out_fragColor;

void main()
{
    PBRMaterial inputs = drp_sample_material(PBR_ALPHA_MASK);
    // Sample normal maps before discard to preserve derivatives at cutout edges.
    PBRSurface surface = pbr_sample_surface(inputs, var_texcoord0);
    if (drp_should_discard(inputs))
    {
        discard;
    }
    PBRLighting lighting = pbr_create_lighting();
    if (!inputs.unlit)
    {
        MaterialInfo material = pbr_create_material_info(inputs);
        lighting.direct = pbr_evaluate_direct_lighting(material, surface, var_view);
        lighting.indirect = pbr_evaluate_ambient_lighting(material, ambient_light());
    }
    // Material AO and screen-space visibility affect indirect light only.
    // Direct lights, emission and unlit base color keep the engine's behavior.
    float visibility = inputs.occlusion * drp_ambient_visibility(surface.position);
    vec3 color = pbr_compose_lighting(inputs, lighting, visibility, visibility);
    out_fragColor = vec4(drp_output(color), pbr_get_alpha(inputs));
}
