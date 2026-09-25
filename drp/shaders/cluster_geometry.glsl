#ifndef DRP_CLUSTER_GEOMETRY_GLSL
#define DRP_CLUSTER_GEOMETRY_GLSL

bool sphere_aabb(vec3 position, float radius, vec3 minimum, vec3 maximum)
{
    // Clamping the sphere center to the box gives the closest point on or in
    // the AABB. The sphere intersects when that point is inside its radius.
    vec3 distance = position - clamp(position, minimum, maximum);
    return dot(distance, distance) <= radius * radius;
}

bool cone_aabb(vec3 position, vec3 direction, float range, float half_angle,
    vec3 minimum, vec3 maximum)
{
    // Reject against the spotlight's range first. The remaining conservative
    // cone test uses the cluster's enclosing sphere to avoid false negatives.
    if (!sphere_aabb(position, range, minimum, maximum))
    {
        return false;
    }

    // A hemisphere or wider cone conservatively uses the range sphere.
    if (half_angle >= 1.57079632679)
    {
        return true;
    }

    vec3 center = (minimum + maximum) * 0.5;
    vec3 extent = (maximum - minimum) * 0.5;
    float cluster_radius = length(extent);
    vec3 offset = center - position;
    float axial_center = dot(offset, direction);
    if (axial_center + cluster_radius < 0.0 || axial_center - cluster_radius > range)
    {
        return false;
    }

    vec3 radial_offset = offset - direction * axial_center;
    float radial_distance = length(radial_offset);
    // The distance to the cone wall must be measured perpendicular to it.
    // Adding the sphere radius in the radial direction alone underestimates
    // overlap and can reject clusters containing illuminated fragments.
    float wall_distance = radial_distance * cos(half_angle) -
        axial_center * sin(half_angle);
    return wall_distance <= cluster_radius;
}

vec3 point_at_depth(vec3 origin, vec3 direction, float depth)
{
    // Defold view space looks down -Z, while the depth values are positive.
    // Orthographic rays have distinct origins instead of sharing the eye.
    return origin + direction * ((-depth - origin.z) / direction.z);
}

#endif
