// Compile the actual GLSL geometry helpers as C++ to test their geometry
// without a GPU. This small vector adapter only supplies GLSL primitives.
#include <algorithm>
#include <cassert>
#include <cmath>
#include <iostream>
#include <random>

struct vec3 {
    float x, y, z;
    vec3(float x_, float y_, float z_) : x(x_), y(y_), z(z_) {}
};
vec3 operator+(vec3 a, vec3 b) { return vec3(a.x+b.x, a.y+b.y, a.z+b.z); }
vec3 operator-(vec3 a, vec3 b) { return vec3(a.x-b.x, a.y-b.y, a.z-b.z); }
vec3 operator*(vec3 a, float b) { return vec3(a.x*b, a.y*b, a.z*b); }
float dot(vec3 a, vec3 b) { return a.x*b.x + a.y*b.y + a.z*b.z; }
float length(vec3 a) { return std::sqrt(dot(a,a)); }
vec3 clamp(vec3 p, vec3 lo, vec3 hi) {
    return vec3(std::max(lo.x,std::min(p.x,hi.x)),
                std::max(lo.y,std::min(p.y,hi.y)),
                std::max(lo.z,std::min(p.z,hi.z)));
}
#include "../drp/shaders/cluster_geometry.glsl"

void near(vec3 actual, vec3 expected) {
    assert(length(actual-expected) < 0.0001f);
}

int main() {
    const vec3 origin(0,0,0), direction(0,0,-1);
    const float pi = 3.14159265358979323846f;
    // Regression: a 90-degree spotlight intersects this actual perspective
    // cluster. Its far corner lies inside the light, despite the old rejection.
    assert(cone_aabb(vec3(-22.228666f,-23.573285f,-8.231693f), direction,
        54.141665f, pi/4, vec3(-4.743082f,-15.810273f,-27.384196f),
        vec3(0,-7.186831f,-17.782794f)));
    assert(!cone_aabb(origin,direction,10,pi/4,vec3(20,20,-5),vec3(21,21,-4)));
    assert(!cone_aabb(origin,direction,10,pi/4,vec3(-1,-1,4),vec3(1,1,5)));
    assert(cone_aabb(origin,direction,10,pi/2,vec3(-1,-1,-1),vec3(1,1,1)));

    // Independently construct points strictly inside a cone and boxes that
    // contain them. A conservative intersection must never reject such boxes.
    std::mt19937 random(921);
    std::uniform_real_distribution<float> unit(0,1);
    for (int i=0; i<20000; ++i) {
        float angle = (5 + 80*unit(random))*pi/180;
        float z = 0.1f + 20*unit(random);
        float radial = z*std::tan(angle)*unit(random)*0.999f;
        float azimuth = 2*pi*unit(random);
        vec3 point(radial*std::cos(azimuth),radial*std::sin(azimuth),-z);
        vec3 extent(0.01f+5*unit(random),0.01f+5*unit(random),0.01f+5*unit(random));
        vec3 center = point + vec3((2*unit(random)-1)*extent.x,
            (2*unit(random)-1)*extent.y,(2*unit(random)-1)*extent.z);
        assert(cone_aabb(origin,direction,length(point)+0.01f,angle,center-extent,center+extent));
    }

    // Orthographic XY stays fixed at every depth; perspective XY scales from
    // the eye. Exercise off-center rays and both slice endpoints.
    for (float depth : {0.1f,1.0f,10.0f,100.0f}) {
        near(point_at_depth(vec3(8,-3,-0.1f),vec3(0,0,-99.9f),depth),vec3(8,-3,-depth));
        near(point_at_depth(vec3(0.08f,-0.03f,-0.1f),vec3(79.92f,-29.97f,-99.9f),depth),
            vec3(0.8f*depth,-0.3f*depth,-depth));
    }
    std::cout << "cluster_geometry_spec: PASS (20,000 conservative-culling cases)\n";
}
