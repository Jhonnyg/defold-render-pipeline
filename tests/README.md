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

The C++ fixture includes the actual GLSL geometry helpers through a small
vector adapter. It checks the spotlight false-negative regression, 20,000
boxes containing known illuminated points, and perspective/orthographic ray
reconstruction. It does not maintain a second copy of the culling algorithm.

The Python checks export an isolated project, verify that the source and scene
files are preserved, and traverse the exported renderer/material shader
references to ensure compute and SSBO resources are unreachable.

These tests do not execute GPU work. Before release, build both shader paths
and run backend smoke scenes for synchronization, shading, alpha coverage,
overflow, transparency, and camera movement. Orthographic cameras with positive
near/far depths use clustering; cameras whose clip range crosses the eye use
conventional shading for that frame.

HDR coverage includes scene/resolve ordering, linear output for each PBR
surface pass, presenter lifetime, target reuse and resize, runtime exposure,
profile/capability fallback, allocation failures, and texture unbinding. The
HDR C++ fixture compiles the actual GLSL tone curve and transfer function,
including highlight values above 1 and the maximum half-float scene value.
