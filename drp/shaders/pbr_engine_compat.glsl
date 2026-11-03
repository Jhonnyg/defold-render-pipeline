#ifndef DRP_PBR_ENGINE_COMPAT_GLSL
#define DRP_PBR_ENGINE_COMPAT_GLSL
// asset-pbr 0.1.0 calls one-argument view helpers. Load the engine declarations
// first, then adapt only asset-pbr's calls so both old and explicit-view engine
// helper signatures work without redeclaring either engine function.
#include "/builtins/materials/lighting.glsl"
vec3 drp_pbr_view_point(vec3 p) { return (var_view * vec4(p, 1.0)).xyz; }
vec3 drp_pbr_view_direction(vec3 d)
{
    vec3 direction = mat3(var_view) * d;
    float length_squared = dot(direction, direction);
    return length_squared > 0.0000000001 ? direction * inversesqrt(length_squared) : vec3(0.0);
}
#define world_to_view_point(p) drp_pbr_view_point(p)
#define world_to_view_dir(d) drp_pbr_view_direction(d)
#endif
