#ifndef DRP_CLUSTERED_CONFIG_GLSL
#define DRP_CLUSTERED_CONFIG_GLSL

// Shader-side half of the clustered-lighting capacity contract. Keep these
// values synchronized with /drp/features/clustered/config.lua until Defold can
// generate Lua and shader constants from one build-time definition.
#define DRP_CLUSTER_LIGHT_CAPACITY 64
#define DRP_CLUSTER_LIST_CAPACITY 64

#endif
