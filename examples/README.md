# Examples

## Sponza clustered shading

[`sponza.collection`](sponza/sponza.collection) is the default bootstrap
collection and the visual integration test for clustered shading. It exercises
asset-pbr metallic-roughness factors, base-color and metallic-roughness maps,
normal maps, opaque and alpha-mask slots, a transparent fixture, one
directional light, and eight local lights spread through the atrium.

The balanced profile renders the actual clustered PBR result by default. To
inspect assignment instead, apply a runtime override with
`lighting.cluster_debug = true`. The diagnostic colors visible geometry: gray
means empty, the blue-to-red ramp shows increasing occupancy, dark lines mark
XY tile edges, and magenta reports overflow.

## Small clustered assignment scene

[`clustered_renderer.collection`](clustered_renderer/clustered_renderer.collection)
is a smaller diagnostic scene with eight colored point lights spread across
several depth slices. Temporarily select it in `game.project` when a minimal
assignment test is preferable to Sponza. Move through either scene with the
Vantage controls.

The project must reserve at least as many engine lights as the clustered shader
ABI exposes:

```ini
[light]
max_count = 64
```

Models enter the clustered passes by using one of
`/drp/materials/clustered_opaque.material`,
`/drp/materials/clustered_mask.material`, or
`/drp/materials/clustered_transparent.material` in their material slots.
Opaque and mask geometry write depth before the transparent pass. Transparent
objects use source-alpha blending with depth writes disabled.

The `compatibility` profile remains a conventional forward path and draws
materials tagged `model`, such as `/defold-pbr/pbr.material`. It deliberately
does not dispatch cluster compute programs or bind cluster SSBOs. Automatic
runtime material-variant selection is not part of this milestone, so content
that must run on compatibility-only devices needs conventional material slots
in its compatibility scene or build variant.

## Quality API

[`quality_api_example.collection`](quality_api_example.collection) demonstrates
the configuration API without rendering any scene content. It:

- initializes DRP safely;
- enumerates registered profiles;
- registers an inherited project profile;
- applies a runtime settings override;
- listens for committed quality transitions; and
- cycles through profiles when the user clicks.

To run it, temporarily change the bootstrap collection in `game.project`:

```ini
[bootstrap]
main_collection = /examples/quality_api/quality_api_example.collectionc
render = /drp/drp.renderc
```

Run the project and click in the game window. The console shows the requested,
effective, and pending profiles. The collection has no scene content, so its
output is intentionally in the console.
