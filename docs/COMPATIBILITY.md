# Compatibility builds

DRP supports runtime quality changes on devices capable of loading its clustered
shaders. A device lacking compute or storage-buffer support needs a separate
compatibility build. Defold eagerly loads `.render` resources and model
materials before Lua runs, so selecting `drp.default_profile = compatibility`
alone cannot prevent unsupported shader resources from being created.

From the project root, run:

```sh
python3 tools/prepare_compatibility.py --output /tmp/drp-compatibility
```

The output must be a new directory outside the source project. Build the output
with your usual Defold editor or Bob command. A host project containing its own
`drp` directory can be selected with `--project /path/to/project`.

The exporter:

- Preserves model and scene files, public material paths, material tags, and
  textures. It changes the three public DRP material resources to their
  conventional opaque, alpha-mask, and transparent shaders.
- Selects `/drp/compatibility.render`, containing only conventional material
  resources, and replaces the exported `/drp/drp.render` with the same contents.
- Sets `drp.clustered_resources = 0`. Requests for `balanced`, `high`, or `ultra`
  resolve to compatibility, even on a capable device. Applications cannot
  restore omitted shaders with `set_capabilities()`.
- Copies cached dependency archives when present, and excludes build outputs,
  Git metadata, and editor caches. The original project remains unchanged.

Only the standard DRP material/render resources are substituted. A host project
with additional custom compute or SSBO resources must exclude or replace those
resources itself. This export retains the project's other requirements,
including its Defold/native-extension revision and GLES shader settings.

Automatic selection between both shader families within a single portable
bundle requires engine support for deferred or optional shader resources. It is
not provided by this project-only export.
