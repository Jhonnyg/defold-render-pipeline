#version 430

// Writes positive linear view-space depth for opaque clustered geometry.
// The compute depth-reduction pass reads this color target; the accompanying
// hardware depth attachment still performs nearest-surface rejection.

in highp vec4 var_position;
layout(location = 0) out vec4 out_fragColor;

void main()
{
    // Camera-forward positions have negative view-space Z in Defold.
    out_fragColor = vec4(vec3(max(-var_position.z, 0.0)), 1.0);
}
