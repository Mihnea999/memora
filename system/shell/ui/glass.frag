#version 440
// Liquid glass, after ybouane/liquidglass (MIT): the sheet is a lens whose rim
// is rounded like a pill (a half-circle bevel). Where the rim slopes, what is
// behind is bent inwards (refraction) and split a little into colours
// (chromatic aberration), and the slope catches light (Fresnel, a thin inner
// stroke brightest at the top). The flat middle stays clear. No shadow.
//
// Built with: /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o glass.frag.qsb glass.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;          // px
    float radius;       // corner radius, px
    float zRadius;      // how far in from the edge the bevel reaches, px
    float refraction;   // 0..1
    float chroma;       // 0..1
    float edgeLight;    // 0..1, the rim's own light
    float fresnel;      // 0..1
    float hasBackdrop;  // 1: `source` is what is behind, refract it
    float darkMode;     // 1: the dark look (light text)
    float adapt;        // 1: Tinted, what is behind is dimmed or lifted under the text; 0: Clear, as ybouane/liquidglass
    vec4 fill;          // the glass tint, premultiplied (Qt hands colours to shaders so)
};
layout(binding = 1) uniform sampler2D source;

float rrSDF(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

float bevelHeight(float d, float zR) {
    if (d <= 0.0) return 0.0;
    if (d >= zR) return zR;
    return sqrt(d * (2.0 * zR - d));
}

void main() {
    vec2 half_ = size * 0.5;
    vec2 p = (qt_TexCoord0 - 0.5) * size;          // px from the centre, y down
    float r = min(radius, min(half_.x, half_.y));
    float sdf = rrSDF(p, half_, r);
    float mask = 1.0 - smoothstep(-1.5, 0.5, sdf);   // as ybouane/liquidglass
    if (mask <= 0.0) { fragColor = vec4(0.0); return; }

    float maxD = min(half_.x, half_.y);
    float inside = -sdf;
    float edge = smoothstep(maxD * 0.35, 0.0, inside);

    // Surface normal of the bevel.
    float zR = max(1.0, zRadius);   // not cut to half the size: a small shape is lens all over, as in the reference
    float e = 2.0;
    float hC = bevelHeight(inside, zR);
    float hR = bevelHeight(-rrSDF(p + vec2(e, 0.0), half_, r), zR);
    float hL = bevelHeight(-rrSDF(p - vec2(e, 0.0), half_, r), zR);
    float hD = bevelHeight(-rrSDF(p + vec2(0.0, e), half_, r), zR);
    float hU = bevelHeight(-rrSDF(p - vec2(0.0, e), half_, r), zR);
    vec2 hGrad = vec2(hR - hL, hD - hU) / (2.0 * e);   // points inwards
    vec3 N = normalize(vec3(-hGrad, 1.0));
    float depth = smoothstep(0.0, zR, inside);

    vec3 col;
    float alpha;
    if (hasBackdrop > 0.5) {
        // Biconvex refraction: light bends at both faces of the rim.
        float refrPow = 1.0 - 1.0 / 1.5;
        float thickNorm = (hC * 2.0) / max(zR * 2.0, 1.0);
        vec2 bend = hGrad * refrPow;
        vec2 refrPx = (bend * 2.0 + bend * thickNorm * 0.5) * refraction * 30.0;
        refrPx += (-p / max(half_, vec2(1.0))) * refraction * 4.0 * depth;
        float caS = chroma * 36.0 * (edge * 0.7 + 0.3);
        vec2 ca = N.xy * caS / size;
        vec2 uv = clamp(qt_TexCoord0 + refrPx / size, vec2(0.0), vec2(1.0));
        col = vec3(texture(source, clamp(uv + ca, 0.0, 1.0)).r,
                   texture(source, uv).g,
                   texture(source, clamp(uv - ca, 0.0, 1.0)).b);
        col *= 1.0 + 0.06 * depth;
        // Adaptive, as the compositor's glass (system/plugin/glass.cpp).
        const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
        float L = mix(dot(texture(source, uv).rgb, LUMA), dot(texture(source, vec2(0.5)).rgb, LUMA), 0.6);
        if (darkMode > 0.5) col *= 1.0 - smoothstep(0.3, 0.95, L) * 0.5 * adapt;
        else col = mix(col, vec3(1.0), smoothstep(0.6, 0.1, L) * 0.45 * adapt);
        col = col * (1.0 - fill.a) + fill.rgb;
        alpha = 1.0;
    } else {
        // The compositor frosts what is behind; only the tint is drawn here.
        // (Its colour, unpremultiplied: multiplied by its alpha twice, a white
        // tint turned into a grey veil that darkened the glass.)
        col = fill.a > 0.0 ? fill.rgb / fill.a : vec3(0.0);
        alpha = fill.a;
    }

    // Light on the glass.
    float fres = pow(1.0 - abs(N.z), 4.0) * fresnel;
    float stroke = smoothstep(-2.5, -1.5, sdf) * (1.0 - smoothstep(-1.0, 0.0, sdf));
    float topBias = 0.5 - 0.5 * (p.y / half_.y);
    stroke *= 0.35 + 0.65 * topBias;
    float rim = edge * edgeLight * 0.22;
    float glow = smoothstep(5.0, 0.0, inside) * edgeLight * 0.15;
    float env = (0.5 - N.y * 0.5) * fres * 0.08;
    float white = clamp(fres * 0.2 + rim + glow + stroke * edgeLight * 0.55 + env, 0.0, 1.0);

    // Premultiplied: the tint, then white light over it.
    vec3 rgb = col * alpha * (1.0 - white) + vec3(white);
    float a = alpha + white * (1.0 - alpha);
    fragColor = vec4(rgb, a) * mask * qt_Opacity;
}
