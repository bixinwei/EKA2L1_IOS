// Cinematic Lighting Enhancement for EKA2L1 iOS.
// GLES 3.0 compatible; the renderer prepends #version 300 es on iOS.
// This is deliberately not a CRT shader: no curvature, scanlines, vignette or
// phosphor mask. A 2D emulator frame has no depth, normal or scene geometry, so
// real ray tracing is impossible here. This shader instead uses screen-space
// highlight diffusion, local contrast and filmic HDR tone mapping to give bright
// lamps, sunsets and specular pixels a restrained simulated-lighting response.
#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

uniform sampler2D sampler0;
uniform vec2 u_texelDelta;
in vec2 r_texcoord;
out vec4 o_color;

float luma(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

// ACES fitted curve. It retains highlight detail instead of simply clipping it.
vec3 filmicTonemap(vec3 color) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), 0.0, 1.0);
}

void main() {
    vec2 uv = r_texcoord;
    vec2 texel = max(u_texelDelta, vec2(0.0001));
    vec3 base = texture(sampler0, uv).rgb;

    // Nine-tap, center-weighted highlight field. Only luminance above the
    // threshold contributes, so ordinary text and flat UI remain sharp.
    vec3 blur = texture(sampler0, uv + texel * vec2(-1.0, -1.0)).rgb * 0.055;
    blur += texture(sampler0, uv + texel * vec2( 0.0, -1.0)).rgb * 0.090;
    blur += texture(sampler0, uv + texel * vec2( 1.0, -1.0)).rgb * 0.055;
    blur += texture(sampler0, uv + texel * vec2(-1.0,  0.0)).rgb * 0.090;
    blur += base * 0.420;
    blur += texture(sampler0, uv + texel * vec2( 1.0,  0.0)).rgb * 0.090;
    blur += texture(sampler0, uv + texel * vec2(-1.0,  1.0)).rgb * 0.055;
    blur += texture(sampler0, uv + texel * vec2( 0.0,  1.0)).rgb * 0.090;
    blur += texture(sampler0, uv + texel * vec2( 1.0,  1.0)).rgb * 0.055;

    vec3 highlightBloom = max(blur - vec3(0.54), 0.0);
    float bright = smoothstep(0.50, 0.92, luma(blur));

    // Small local-contrast lift produces cleaner material separation without
    // sharpening halos. Warm highlights and cool shadows are intentionally subtle.
    vec3 localContrast = base + (base - blur) * 0.16;
    float shadow = 1.0 - smoothstep(0.10, 0.48, luma(base));
    vec3 simulatedBounce = highlightBloom * vec3(1.00, 0.96, 0.88) * (0.24 + bright * 0.18);
    simulatedBounce += shadow * highlightBloom * vec3(0.035, 0.055, 0.085);

    vec3 enhanced = max(localContrast + simulatedBounce, 0.0);
    o_color = vec4(filmicTonemap(enhanced * 1.08), 1.0);
}
