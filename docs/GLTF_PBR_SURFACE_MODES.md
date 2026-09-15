# Native glTF PBR Surface Modes

## Status

This is a deferred engine design proposal. It records the intended handling of
glTF opaque, alpha-mask, and alpha-blended materials so the work can be resumed
without making it part of the current DRP clustered-lighting milestone.

DRP currently uses explicit opaque, mask, and transparent materials. That is a
functional integration path, but native glTF interpretation and default PBR
rendering should ultimately belong to Defold rather than each render extension.

## Problem

A glTF material's alpha mode changes draw-level behavior, not only the value
returned by its fragment shader. The renderer must classify the draw before it
can select depth writes, blending, sorting, culling, depth/shadow variants, and
the render phase.

The three baseline modes require different behavior:

| glTF mode | Fragment behavior | Depth write | Blending | Ordering |
| --- | --- | --- | --- | --- |
| `OPAQUE` | Ignore output alpha for coverage. | On | Off | Normally front-to-back. |
| `MASK` | Discard coverage below `alphaCutoff`. | On | Off | Normally front-to-back. |
| `BLEND` | Preserve fractional coverage. | Normally off | Alpha blend | Normally back-to-front. |

`doubleSided` also affects culling. The same classification is needed by color,
depth-only, and shadow-caster passes. It cannot be recovered reliably from a
generic material URL or postponed until fragment execution.

Without a native semantic model:

- users must manually assign a material to every imported slot;
- extensions independently recreate glTF import and classification logic;
- reimport can make material maintenance error-prone;
- a scene may need duplicate material or model setup for different pipelines;
- an incorrect material silently produces wrong depth, masks, or blending; and
- Defold cannot provide correct PBR/glTF behavior out of the box.

## Design goals

- Preserve glTF material intent through import, build, editor, and runtime.
- Give newly imported glTF models a correct built-in PBR result by default.
- Keep surface classification independent of the selected render pipeline.
- Let render scripts and extensions consume semantic render phases.
- Preserve explicit per-slot custom material overrides across reimport.
- Share material data and textures between color, depth, and shadow variants.
- Keep custom materials and custom render scripts fully supported.

This proposal does not require advanced order-independent transparency. The
native baseline should first implement the behavior required for ordinary glTF
alpha blending and object-level sorting.

## 1. Preserve imported material semantics

The model/material build data should retain a structured surface description.
Conceptually it contains:

```text
surface mode: opaque | mask | blend
alpha cutoff: number
double sided: boolean
unlit: boolean
PBR factors and texture bindings
supported glTF material-extension metadata
```

The exact engine type and serialization format remain design decisions. The
important property is that the values remain semantic data rather than being
encoded only as shader constants or inferred from material filenames.

The importer should read at least:

- `alphaMode`;
- `alphaCutoff`;
- `doubleSided`;
- the unlit extension;
- base-color, metallic, roughness, normal, occlusion, and emissive data; and
- enough extension metadata to select future PBR variants without changing the
  surface-mode contract.

## 2. Select a semantic PBR family

Import should map the glTF mode to a semantic family:

```text
OPAQUE -> PBR opaque
MASK   -> PBR mask
BLEND  -> PBR transparent
```

This is not yet a choice between conventional forward and clustered lighting.
It answers which render phase and coverage rules the surface requires.

The engine should expose the classification to the renderer directly. Material
tags may remain useful for application-specific grouping, but an extension
should not need to invent tags merely to rediscover standard glTF behavior.

## 3. Preserve explicit slot overrides

An imported material slot should distinguish between automatic and explicit
selection:

```text
Automatic: use imported glTF/PBR semantics
Explicit:  use /project/materials/custom.material
```

Automatic slots follow updated source metadata after reimport. Explicit slots
remain authoritative and must not be silently replaced. Projects need the
override for water, particles, additive effects, custom depth behavior, or any
shader outside the built-in PBR family.

Ideally the editor shows the inferred surface mode and its source so users can
understand why a slot enters a particular pass.

## 4. Resolve semantic families to pass variants

A built-in PBR family should be able to provide variants such as:

```text
PBR family
|-- color opaque
|-- color mask
|-- color transparent
|-- depth opaque
|-- depth mask
|-- shadow opaque
`-- shadow mask
```

The color implementation can then vary by active render pipeline without
changing model content:

```text
PBR mask
|-- default forward renderer -> conventional PBR mask program
`-- DRP Forward+            -> clustered PBR mask program
```

Textures, factors, alpha cutoff, and other per-slot values remain attached to
the render entry. Only the compatible program/pass implementation changes.

This likely needs an engine material-family or material-variant mechanism. The
engine should provide the built-in variants and a stable way for extensions to
register or select compatible alternatives. The extension should not rewrite
component material URLs every frame.

## Render-phase responsibilities

The engine should provide a correct default policy and enough semantic data for
custom renderers:

### Opaque

- Opaque render phase.
- Depth test and writes enabled.
- Blending disabled.
- Eligible for depth and shadow passes.
- Culling derived from `doubleSided` unless explicitly overridden.

### Alpha mask

- Masked render phase or an explicitly identifiable opaque sub-phase.
- The same alpha cutoff in color, depth, and shadow passes.
- Depth test and writes enabled.
- Blending disabled.
- Culling derived from `doubleSided`.

### Alpha blend

- Transparent render phase after opaque and mask geometry.
- Depth testing enabled and depth writes normally disabled.
- glTF-compatible alpha blending.
- Object/render-entry back-to-front sorting.
- Culling derived from `doubleSided`.

Custom renderers remain responsible for choosing their pass organization and
may override state. The engine responsibility is to preserve intent, provide a
correct built-in path, and expose reliable classification.

## Transparency quality boundary

Native baseline support should guarantee correct ordinary glTF behavior:

- proper mode classification;
- matching color/depth/mask behavior;
- blending and depth state;
- double-sided handling; and
- object-level back-to-front sorting.

That does not solve triangle ordering within one mesh, intersecting transparent
objects, refraction, or transmission. Weighted blended OIT, depth peeling, and
similar techniques are advanced pipeline choices. The engine should expose the
resources and hooks needed to implement them, while DRP or another renderer may
choose the actual technique and quality tier.

## Ownership boundary

| Responsibility | Owner |
| --- | --- |
| Import and preserve glTF surface metadata | Engine/editor/build pipeline |
| Built-in PBR materials and correct default rendering | Engine |
| Semantic opaque, mask, and transparent classification | Engine |
| Per-slot automatic/explicit override behavior | Engine/editor |
| Material-family or pass-variant API | Engine |
| Conventional versus clustered color implementation | Render pipeline/extension |
| Cluster assignment and clustered BRDF light lookup | DRP |
| Optional OIT technique and quality selection | Render pipeline/extension |

## Suggested implementation stages

1. Preserve alpha mode, cutoff, double-sided, unlit, and PBR feature metadata in
   imported model material data and expose it in the editor/runtime.
2. Add automatic built-in PBR opaque, mask, and transparent selection while
   preserving explicit material overrides.
3. Expose semantic render phases and consistent default render state.
4. Add reusable depth and shadow-caster variants with identical mask coverage.
5. Introduce a material-family/variant API that lets render extensions supply
   alternatives without duplicating model resources.
6. Consider advanced transparency infrastructure separately after the native
   glTF baseline is stable.

## DRP interim behavior

Until this engine work exists, DRP uses explicit clustered opaque, mask, and
transparent materials. At runtime it can override those predicates with
matching conventional asset-pbr programs when the compatibility profile is
selected. This keeps one authored scene usable by both DRP paths, but initial
slot classification and material assignment remain manual.

## Acceptance criteria

- Importing an unmodified glTF produces the expected opaque, cutout, and
  transparent result with the default renderer.
- Alpha cutoff is identical in color, depth, and shadow passes.
- Transparent entries render after opaque/masked entries with appropriate
  depth and blend state.
- `doubleSided` consistently affects all relevant variants.
- Reimport updates automatic slots without replacing explicit overrides.
- A render extension can choose a clustered implementation without duplicating
  the model or losing material bindings.

