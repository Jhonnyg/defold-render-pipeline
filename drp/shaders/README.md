# Shaders

Shared shader libraries live here; compute programs remain with their owning
feature. The current files implement clustered PBR opaque, masked, and
transparent variants plus linear-depth prepass fragments. Their public material
usage and internal buffer contract are documented in
`/docs/CLUSTERED_LIGHTING.md`.
