// Lightweight runtime color enhancement. No CRT, bloom or geometry synthesis.
#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

uniform sampler2D sampler0;
uniform float uExposure;
uniform float uSaturation;
in vec2 r_texcoord;
out vec4 o_color;

void main() {
    vec3 color = texture(sampler0, r_texcoord).rgb;
    color *= exp2(uExposure);
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(luma), color, uSaturation);
    o_color = vec4(clamp(color, 0.0, 1.0), 1.0);
}
