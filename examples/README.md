# Examples

## Clustered renderer

[`clustered_renderer.collection`](clustered_renderer/clustered_renderer.collection)
is the default bootstrap collection. It uses DRP clustered materials and eight
colored point lights spread across several depth slices. Move with the Vantage
controls to inspect cluster transitions.

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
