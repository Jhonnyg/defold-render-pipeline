# Shaders

Shared shader libraries live here; compute programs remain with their owning
feature. The current files implement clustered PBR opaque, masked, and
transparent variants around asset-pbr's complete PBR lighting module, plus the
shared cluster occupancy/overflow visualization. Public material usage and the
active buffer contract are documented in `/docs/CLUSTERED_LIGHTING.md`.
