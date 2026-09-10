# Examples

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
main_collection = /examples/quality_api_example.collectionc
render = /drp/drp.renderc
```

Run the project and click in the game window. The console shows the requested,
effective, and pending profiles. Because this milestone contains no rendering,
the game window remains empty; the example's output is intentionally in the
console.

Additional focused examples will be added as rendering features are
implemented.
