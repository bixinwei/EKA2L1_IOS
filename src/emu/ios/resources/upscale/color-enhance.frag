// Lightweight runtime color enhancement. No CRT, bloom or geometry synthesis.
#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

// The upscale renderer binds the source texture to the sampler0 convention.
uniform sampler2D u_tex;
uniform vec4 u_color;
uniform float uExposure;
uniform float uSaturation;
in vec2 r_texcoord;
out vec4 o_color;

void main() {
    vec3 color = texture(u_tex, r_texcoord).rgb * (u_color.rgb / 255.0);
    color *= exp2(uExposure);
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(luma), color, uSaturation);
    o_color = vec4(clamp(color, 0.0, 1.0), 1.0);
}
