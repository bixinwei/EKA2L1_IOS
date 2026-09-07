// Fantasy CRT + light bloom for EKA2L1 iOS.
// GLES 3.0 compatible; the renderer prepends #version 300 es on iOS.
// This is a screen-space post-process, not hardware ray tracing: bright pixels receive
// a restrained directional glow so it remains viable on iPhone GPUs.
#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

uniform sampler2D sampler0;
uniform vec2 u_texelDelta;
uniform vec2 u_pixelDelta;
in vec2 r_texcoord;
out vec4 o_color;

float luminance(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
    vec2 uv = r_texcoord;
    // Slight barrel curvature evokes a CRT without cutting off meaningful UI content.
    vec2 p = uv * 2.0 - 1.0;
    p *= 1.0 + vec2(p.y * p.y, p.x * p.x) * 0.018;
    vec2 curvedUv = p * 0.5 + 0.5;
    if (curvedUv.x < 0.0 || curvedUv.x > 1.0 || curvedUv.y < 0.0 || curvedUv.y > 1.0) {
        o_color = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    vec3 base = texture(sampler0, curvedUv).rgb;
    // Lightweight cross blur: bright source pixels bleed into nearby pixels as a faux light chase.
    vec2 dx = vec2(u_texelDelta.x * 2.0, 0.0);
    vec2 dy = vec2(0.0, u_texelDelta.y * 2.0);
    vec3 nearLight = texture(sampler0, curvedUv + dx).rgb + texture(sampler0, curvedUv - dx).rgb
                   + texture(sampler0, curvedUv + dy).rgb + texture(sampler0, curvedUv - dy).rgb;
    nearLight *= 0.25;
    float glow = smoothstep(0.52, 0.95, luminance(nearLight));
    // A diagonal component makes highlights trail subtly like a stylised moving light beam.
    vec3 streak = texture(sampler0, curvedUv + (dx + dy) * 2.0).rgb
                + texture(sampler0, curvedUv - (dx + dy) * 2.0).rgb;
    vec3 bloom = max(nearLight - vec3(0.42), 0.0) * 0.34 + max(streak * 0.5 - vec3(0.48), 0.0) * 0.18;

    vec3 color = base + bloom * (0.55 + glow * 0.45);
    // Scanlines, aperture grille and a warm phosphor tint form the Fantasy CRT look.
    float scan = 0.88 + 0.12 * sin(curvedUv.y / max(u_pixelDelta.y, 0.0001) * 3.14159265);
    float triad = mod(floor(curvedUv.x / max(u_pixelDelta.x, 0.0001)), 3.0);
    vec3 mask = triad < 1.0 ? vec3(1.06, 0.93, 0.93) : (triad < 2.0 ? vec3(0.93, 1.06, 0.93) : vec3(0.93, 0.93, 1.06));
    float vignette = 1.0 - dot(p * 0.30, p * 0.30);
    color *= scan * mask * clamp(vignette, 0.78, 1.0);
    color = pow(max(color, 0.0), vec3(0.91));
    o_color = vec4(color, 1.0);
}
