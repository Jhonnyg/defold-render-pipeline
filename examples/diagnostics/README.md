# Regular forward-rendering diagnostic

This scene is used as a staged isolation test. The built-in render script,
DRP compatibility path, clustered compute/SSBO path with conventional
materials, and a resource-free clustered graphics program all rendered
correctly. A clustered graphics program using the three fragment SSBOs also
rendered correctly, as did the complete clustered fragment UBO. The current
seventh stage adds:

- `defold-pbr/pbr.material` and its unmodified shaders;
- regular model components;
- the engine-owned `LightBuffer` populated by ordinary light components;
- DRP's render script and camera/state setup;
- the `balanced` profile, which allocates and binds the cluster storage buffers
  and dispatches the cluster compute shaders;
- a flat `ProbeLightBuffer` containing only `vec4` values, explicitly placed
  alone at set 3, binding 0. Its non-reserved name prevents the engine from
  binding the external light UBO;
- bounded reads from the header and first light so the complete block remains
  reflected and automatically bound;
- no samplers, PBR material UBO, PBR includes, or cluster-index calculations.

`game.project` is temporarily configured to boot this scene in the seventh-stage
configuration. The middle cube should remain solid and three-dimensional, with
RGB normal visualization instead of PBR lighting. The shader reads both the
LightBuffer header and its first array element only through sentinel comparisons;
ordinary light values cannot wash out the normal colours. If it still flattens,
any additional fragment UBO is sufficient to reproduce the failure. If it
becomes correct, the fault is isolated to Defold's nested-struct UBO reflection
or uniform enumeration rather than its size, descriptor set, or external
binding.
