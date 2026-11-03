# Regression checks

Run from the project root with LuaJIT (or a compatible Lua runtime), Python 3,
and a C++11 compiler:

```sh
luajit tests/run.lua
python3 tests/compatibility_spec.py
c++ -std=c++11 -O2 tests/cluster_geometry_spec.cpp -o /tmp/drp-geometry-spec
/tmp/drp-geometry-spec
c++ -std=c++11 -O2 tests/hdr_math_spec.cpp -o /tmp/drp-hdr-math-spec
/tmp/drp-hdr-math-spec
```

The Lua tests exercise quality selection, required device-limit boundaries,
4K dispatches, projection changes, compatibility exports, allocation sizing,
and resize/profile transitions with mocked rendering and native APIs.

The shadow checks cover frame-boundary settings, diagnostic isolation, atomic
six-face atlas allocations, bounded configuration, cache hits/invalidation,
compact light-index changes, update-budget deferral, selective tile clearing,
resource lifetime, and recovery after failed submissions/draws. Renderer tests
mock view construction; use the three-light example for actual projection and
GPU validation.

The C++ fixture includes the actual GLSL geometry helpers through a small
vector adapter. It checks the spotlight false-negative regression, 20,000
boxes containing known illuminated points, and perspective/orthographic ray
reconstruction. It does not maintain a second copy of the culling algorithm.

The Python checks export an isolated project, verify that the source and scene
files are preserved, and traverse the exported renderer/material shader
references to ensure compute and SSBO resources are unreachable.

## Native context lifecycle

The native fixture compiles the actual extension lifecycle, graphics bridge,
fullscreen submission, and Lua bindings against real Lua. It mocks graphics,
render, resource, and registry services to check independent contexts, buffer
ownership, reset behavior, failed startup, and Lua detachment. Fullscreen checks
cover triangle coverage and UVs, per-frame submission, material reuse and reload,
allocation failures, and cleanup before the render context is destroyed.

Shadow-native checks additionally cover cross-Lua-world registrations,
transactional property validation, stale/deleted versioned light handles,
per-frame index compaction, explicit geometry invalidation and float packing.

Use a built Defold checkout with the context registry, SSBO, and new light APIs.
Install its current SDK headers (including gamesys `comp_light.h` and render
`LightInstanceRenderData`) before compiling; do not mix old headers with new libraries. The command
below uses its installed SDK, generated headers, and host `liblua`/`libdlib`
archives; adjust the SDK path and host platform to your build:

```sh
DRP_SDK_ROOT=/path/to/defold/tmp/dynamo_home
DRP_HOST_PLATFORM=arm64-macos
c++ -std=c++11 -Wall -Wextra -fsanitize=address,undefined \
    -fno-omit-frame-pointer '-DDLIB_LOG_DOMAIN="DRP"' \
    -isystem "$DRP_SDK_ROOT/sdk/include" \
    -isystem "$DRP_SDK_ROOT/include" \
    -isystem "$DRP_SDK_ROOT/ext/include" \
    tests/native_context_spec.cpp \
    drp/src/drp.cpp drp/src/drp_graphics.cpp drp/src/drp_script.cpp \
    drp/src/drp_fullscreen.cpp drp/src/drp_shadows.cpp \
    "$DRP_SDK_ROOT/lib/$DRP_HOST_PLATFORM/liblua.a" \
    "$DRP_SDK_ROOT/lib/$DRP_HOST_PLATFORM/libdlib.a" \
    -o /tmp/drp-native-context-spec
/tmp/drp-native-context-spec
```

These tests do not execute GPU work. Before release, build both shader paths
and run backend smoke scenes for synchronization, shading, alpha coverage,
overflow, transparency, and camera movement. Orthographic cameras with positive
near/far depths use clustering; cameras whose clip range crosses the eye use
conventional shading for that frame.

HDR coverage includes scene/resolve ordering, linear output for each PBR
surface pass, activation without scene objects, per-frame fullscreen submission,
submission failure/recovery, target reuse and resize, runtime exposure,
profile/capability fallback, missing/old native bridges, allocation failures,
and texture unbinding. The HDR C++ fixture compiles the actual GLSL tone curve
and transfer function,
including highlight values above 1 and the maximum half-float scene value.

## Shadow runtime smoke

Build an engine containing the current DRP extension against the new light SDK,
then run the disposable scene with a **matching** Bob version:

```sh
python3 tests/run_shadow_smoke.py --bob /path/to/bob.jar --engine /path/to/dmengine
```

The default platform is `arm64-macos`; pass `--platform` for another host. The
runner reuses cached dependencies, builds only resources, freezes example
geometry, and exits after explicit frame assertions. It verifies actual native
registration, all three light projections, nine rendered views, cache reuse,
explicit invalidation, point-only invalidation, disable/re-enable, hard/PCF/PCSS
shader execution and cleanup. Assertion failures exit nonzero. This is a GPU
execution/lifecycle check; it does not replace visual review of bias, cascade
transitions, point seams, animated silhouettes and alpha-masked geometry.
