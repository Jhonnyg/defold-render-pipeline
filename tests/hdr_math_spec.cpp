#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdio>

// Compile the production GLSL curve as C++ to exercise highlight range and
// transfer-function boundaries without maintaining a second implementation.
struct vec3 {
    float x, y, z;
    vec3(float v) : x(v), y(v), z(v) {}
    vec3(float a, float b, float c) : x(a), y(b), z(c) {}
};
struct bvec3 { bool x, y, z; };
vec3 operator+(vec3 a, vec3 b) { return vec3(a.x+b.x,a.y+b.y,a.z+b.z); }
vec3 operator-(vec3 a, vec3 b) { return vec3(a.x-b.x,a.y-b.y,a.z-b.z); }
vec3 operator*(vec3 a, vec3 b) { return vec3(a.x*b.x,a.y*b.y,a.z*b.z); }
vec3 operator/(vec3 a, vec3 b) { return vec3(a.x/b.x,a.y/b.y,a.z/b.z); }
vec3 max(vec3 a, vec3 b) { return vec3(std::max(a.x,b.x),std::max(a.y,b.y),std::max(a.z,b.z)); }
vec3 clamp(vec3 a, vec3 lo, vec3 hi) {
    return vec3(std::min(std::max(a.x,lo.x),hi.x),
                std::min(std::max(a.y,lo.y),hi.y),std::min(std::max(a.z,lo.z),hi.z));
}
vec3 pow(vec3 a, vec3 b) { return vec3(std::pow(a.x,b.x),std::pow(a.y,b.y),std::pow(a.z,b.z)); }
bvec3 lessThanEqual(vec3 a, vec3 b) { return { a.x<=b.x, a.y<=b.y, a.z<=b.z }; }
vec3 mix(vec3 a, vec3 b, bvec3 t) { return vec3(t.x?b.x:a.x,t.y?b.y:a.y,t.z?b.z:a.z); }

#include "../drp/features/hdr/tonemap.glsl"

int main() {
    assert(drp_tonemap(vec3(0), 0).x == 0);
    assert(drp_tonemap(vec3(-1), 0).x == 0);
    assert(std::abs(drp_linear_to_srgb(vec3(0.0031308f)).x - 0.04044994f) < 1e-6f);
    assert(std::abs(drp_tonemap(vec3(0.18f), 0).x - 0.5534576f) < 1e-5f);
    assert(drp_tonemap(vec3(2), 0).x > drp_tonemap(vec3(1), 0).x);
    float previous = -1;
    for (int i=0; i<=10000; ++i) {
        const float input = i / 1000.0f;
        const float color = drp_tonemap(vec3(input), 0).x;
        assert(std::isfinite(color) && color >= 0 && color <= 1.000001f);
        assert(color + 1e-6f >= previous);
        assert(std::abs(drp_tonemap(vec3(input), 1).x - drp_tonemap(vec3(input*2), 0).x) < 1e-6f);
        previous = color;
    }
    const float brightest = drp_tonemap(vec3(65504), 16).x;
    assert(std::isfinite(brightest) && std::abs(brightest-1) < 1e-6f);
    std::puts("hdr_math_spec: PASS");
}
