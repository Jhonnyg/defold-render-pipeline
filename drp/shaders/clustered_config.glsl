#ifndef DRP_CLUSTERED_CONFIG_GLSL
#define DRP_CLUSTERED_CONFIG_GLSL

// Compile-time capacity contract shared by cluster compute and fragment
// shaders. Keep these values synchronized with
// /drp/features/clustered/config.lua until Defold can generate Lua and shader
// constants from one build-time definition.
#define DRP_CLUSTER_LIGHT_CAPACITY 64
#define DRP_CLUSTER_LIST_CAPACITY 64

#endif
