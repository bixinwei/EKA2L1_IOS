#version 140

uniform sampler2D u_tex;
uniform vec4 u_color;
uniform float uExposure;
uniform float uSaturation;

in vec2 r_texcoord;
out vec4 o_color;

void main() {
    vec4 sampled = texture(u_tex, r_texcoord) * (u_color / 255.0);
    vec3 color = sampled.rgb * exp2(uExposure);
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(luma), color, uSaturation);
    o_color = vec4(clamp(color, 0.0, 1.0), sampled.a);
}
