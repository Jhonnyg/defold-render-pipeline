# Materials

The current DRP materials provide clustered PBR opaque, alpha-mask, and
transparent variants. Applications use these variants in model material slots;
they use the engine's built-in glTF vertex and lighting modules while DRP supplies
each fragment's compact clustered light list. Occupancy and overflow remain
available through the `lighting.cluster_debug` diagnostic override. See
`/docs/CLUSTERED_LIGHTING.md`. The render script also owns matching depth-only
and conventional compatibility overrides; applications should not assign those
internal materials directly.
