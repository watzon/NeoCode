#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

constant int MAX_STEPS = 36;
constant float MAX_DIST = 12.0;
constant float SURF_DIST = 0.0035;

float smin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * h * k * (1.0 / 6.0);
}

float sphere(float3 p, float r) {
    return length(p) - r;
}

float2x2 rot(float a) {
    float s = sin(a);
    float c = cos(a);
    return float2x2(c, -s, s, c);
}

float scene(float3 p, float time, float energy, float pulse) {
    float t = time * mix(0.85, 1.02, clamp(energy, 0.0, 1.0));

    float3 c1 = float3(0.82 * cos(t * 0.91 + 0.10), 0.58 * sin(t * 0.73 + 1.20), 0.22 * sin(t * 0.61 + 0.40));
    float3 c2 = float3(-0.68 * cos(t * 0.57 + 1.80), 0.74 * sin(t * 0.96 + 0.20), -0.20 * sin(t * 0.88 + 2.10));
    float3 c3 = float3(0.61 * cos(t * 1.07 + 2.50), -0.79 * sin(t * 0.69 + 2.90), 0.19 * sin(t * 0.53 + 1.60));
    float3 c4 = float3(-0.86 * cos(t * 0.76 + 3.40), -0.52 * sin(t * 1.11 + 1.10), -0.23 * sin(t * 0.72 + 0.90));
    float3 c5 = float3(0.22 * cos(t * 1.18 + 4.10), 0.34 * sin(t * 0.64 + 2.40), 0.28 * sin(t * 0.97 + 2.80));

    float3 q = p;
    q.xy = rot(0.28 * sin(time * 0.55 + p.z * 1.4) + 0.10 * sin(p.y * 2.3 + time * 0.7)) * q.xy;
    q.xz = rot(0.21 * sin(time * 0.43 + p.y * 1.3) + 0.08 * cos(p.x * 2.0 - time * 0.5)) * q.xz;
    q.yz = rot(0.16 * sin(time * 0.38 + p.x * 1.6)) * q.yz;

    float swell = 1.0 + energy * 0.05 + pulse * 0.10;

    float r1 = (0.64 + 0.08 * sin(t * 1.21 + 0.3)) * swell;
    float r2 = (0.59 + 0.09 * sin(t * 0.93 + 2.0)) * swell;
    float r3 = (0.62 + 0.07 * sin(t * 1.34 + 1.4)) * swell;
    float r4 = (0.58 + 0.10 * sin(t * 0.82 + 3.1)) * swell;
    float r5 = (0.55 + 0.08 * sin(t * 1.47 + 2.6)) * swell;

    float d = sphere(q - c1, r1);
    d = smin(d, sphere(q - c2, r2), 0.62);
    d = smin(d, sphere(q - c3, r3), 0.58);
    d = smin(d, sphere(q - c4, r4), 0.64);
    d = smin(d, sphere(q - c5, r5), 0.70);
    d = smin(d, sphere(p - float3(0.06, -0.04, 0.02), (0.68 + 0.05 * sin(t * 0.74)) * swell), 0.78);

    float rippleA = 0.055 * sin(4.2 * p.x + 3.3 * p.y + 2.1 * p.z + time * 1.6);
    float rippleB = 0.040 * sin(5.1 * p.y - 2.7 * p.z + time * 1.2 + 1.7);
    float rippleC = 0.028 * sin(6.4 * p.x - 3.8 * p.y + time * 1.9 + 0.8);
    d += (rippleA + rippleB + rippleC) * (0.55 + energy * 0.08 + pulse * 0.12);

    return d;
}

float raymarch(float3 ro, float3 rd, float time, float energy, float pulse) {
    float dist = 0.0;
    for (int i = 0; i < MAX_STEPS; i++) {
        float3 p = ro + rd * dist;
        float d = scene(p, time, energy, pulse);
        if (d < SURF_DIST) {
            return dist;
        }
        dist += max(d * 0.94, SURF_DIST);
        if (dist > MAX_DIST) {
            break;
        }
    }
    return -1.0;
}

float3 calcNormal(float3 p, float time, float energy, float pulse) {
    float2 e = float2(0.0040, 0.0);
    return normalize(float3(
        scene(p + e.xyy, time, energy, pulse) - scene(p - e.xyy, time, energy, pulse),
        scene(p + e.yxy, time, energy, pulse) - scene(p - e.yxy, time, energy, pulse),
        scene(p + e.yyx, time, energy, pulse) - scene(p - e.yyx, time, energy, pulse)
    ));
}

float3 palette(float t) {
    float3 indigo = float3(0.294, 0.0, 0.510);
    float3 violet = float3(0.545, 0.0, 1.0);
    float3 magenta = float3(1.0, 0.06, 0.58);
    float3 orange = float3(1.0, 0.27, 0.0);
    float3 gold = float3(1.0, 0.93, 0.68);

    float3 c = mix(indigo, violet, smoothstep(0.00, 0.24, t));
    c = mix(c, magenta, smoothstep(0.18, 0.56, t));
    c = mix(c, orange, smoothstep(0.48, 0.84, t));
    c = mix(c, gold, smoothstep(0.80, 1.00, t));
    return c;
}

float4 renderLivingNodeSample(float2 position, float2 size, float time, float energy, float pulse, float warmth) {
    float2 uv = (position - 0.5 * size) / min(size.x, size.y);
    uv *= 1.82 - energy * 0.06 - pulse * 0.08;

    float3 ro = float3(0.0, 0.0, 4.8);
    float3 rd = normalize(float3(uv, -2.8));
    float dist = raymarch(ro, rd, time, energy, pulse);

    if (dist < 0.0) {
        float halo = exp(-6.5 * pow(length(uv * float2(0.92, 1.0)), 2.2));
        float alpha = halo * 0.045;
        float3 tint = mix(float3(0.16, 0.02, 0.42), float3(0.42, 0.06, 0.16), clamp(1.0 - length(uv), 0.0, 1.0));
        return float4(tint * alpha, alpha);
    }

    float3 p = ro + rd * dist;
    float3 n = calcNormal(p, time, energy, pulse);

    float3 light1 = normalize(float3(-0.65, 0.85, 0.55));
    float3 light2 = normalize(float3(0.85, 0.10, 0.35));
    float3 view = normalize(-rd);
    float3 half1 = normalize(light1 + view);
    float3 half2 = normalize(light2 + view);

    float diff1 = max(dot(n, light1), 0.0);
    float diff2 = max(dot(n, light2), 0.0);
    float fresnel = pow(1.0 - max(dot(n, view), 0.0), 2.6);
    float spec1 = pow(max(dot(n, half1), 0.0), 36.0);
    float spec2 = pow(max(dot(n, half2), 0.0), 20.0);

    float angle = atan2(p.y, p.x);
    float swirl = 0.5 + 0.5 * sin(angle + time * 0.9 + p.z * 0.8);
    float radial = 1.0 - smoothstep(0.12, 1.55, length(p.xy));
    float heightMix = 0.5 + 0.5 * p.z;
    float marbling = 0.5 + 0.5 * sin(3.6 * p.x - 2.8 * p.y + 4.0 * p.z + time * 1.3);
    float colorT = clamp(swirl * 0.32 + radial * 0.32 + heightMix * 0.08 + marbling * 0.28 + warmth * 0.14, 0.0, 1.0);

    float3 base = palette(colorT);
    float3 core = palette(clamp(0.72 + radial * 0.35, 0.0, 1.0));
    float3 color = mix(base, core, radial * 0.55);

    color *= 0.56 + diff1 * 0.42 + diff2 * 0.18;
    color += float3(1.0, 0.95, 0.92) * spec1 * (0.18 + energy * 0.05);
    color += float3(1.0, 0.72, 0.82) * spec2 * (0.07 + pulse * 0.03);
    color += mix(float3(0.38, 0.08, 0.92), float3(1.0, 0.28, 0.10), radial) * fresnel * 0.32;

    float surfaceDist = scene(p, time, energy, pulse);
    float edgeGlow = exp(-12.0 * abs(surfaceDist));
    float aura = exp(-2.8 * max(scene(ro + rd * max(dist - 0.05, 0.0), time, energy, pulse), 0.0));
    color += mix(float3(0.22, 0.04, 0.62), float3(1.0, 0.18, 0.34), radial) * edgeGlow * 0.13;

    float sweep = smoothstep(0.80, 1.0, 0.5 + 0.5 * cos(angle - time * 1.35 + 0.6 * sin(time * 0.7)));
    color += float3(1.0, 0.40, 0.22) * sweep * (1.0 - radial) * 0.22;
    color += float3(0.88, 0.18, 1.0) * (1.0 - sweep) * (1.0 - radial) * 0.05;
    color += float3(1.0, 0.58, 0.18) * warmth * (0.08 + pulse * 0.08);
    color += mix(float3(0.10, 0.02, 0.30), float3(0.35, 0.04, 0.10), radial) * aura * 0.14;

    float alpha = clamp(0.84 + fresnel * 0.14 + edgeGlow * 0.08 + pulse * 0.06, 0.0, 1.0);
    return float4(color * alpha, alpha);
}

[[ stitchable ]] half4 livingNodeOrb(float2 position, half4 currentColor, float2 size, float time, float energy, float pulse, float warmth) {
    constexpr float2 sampleOffsets[4] = {
        float2(-0.35, -0.35),
        float2(0.35, -0.35),
        float2(-0.35, 0.35),
        float2(0.35, 0.35)
    };

    float4 accumulated = float4(0.0);
    for (int i = 0; i < 4; i++) {
        accumulated += renderLivingNodeSample(position + sampleOffsets[i], size, time, energy, pulse, warmth);
    }

    float4 color = accumulated * 0.25;
    return half4(half3(color.rgb), half(color.a));
}
