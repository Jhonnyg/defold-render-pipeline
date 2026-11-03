# Shadow example

Set `bootstrap.main_collection` to `/examples/shadows/shadows.collectionc` and
keep `/drp/drp.render` as the renderer. Use an engine containing DRP and the new
light dmSDK API. The scene has directional, point and spot shadow lights plus a
moving cube. The camera uses the same Vantage controls as the clustered example.

Each light GO has a `shadow_caster.script` next to `#light`; the models need no
extra components. Try changing the caster `softness`, `bias`, `normal_bias`, and
`priority` properties or switching the `balanced`/`high` profiles.

To test caching, stop the cube animation and set `cache=true` on the casters.
`drp.get_feature_diagnostics("shadows").cached_views` should increase and
`updated_views` should become zero while the camera and lights are still.
Call `drp.invalidate_shadows()` after changing static geometry. Moving a light
invalidates its own map; moving the camera invalidates affected directional
cascades. Point/spot maps can survive camera motion.
