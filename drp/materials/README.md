# Materials

The current DRP materials provide clustered PBR opaque, alpha-mask, and
transparent variants, together with internal linear-depth override materials.
Applications should use the clustered PBR variants in model material slots and
treat the linear-depth materials as pipeline implementation details. See
`/docs/CLUSTERED_LIGHTING.md`.
