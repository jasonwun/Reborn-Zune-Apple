#include <metal_stdlib>
using namespace metal;

// Two-point-light + ambient color-effect shader. SwiftUI's `.colorEffect`
// modifier passes `position` (in the layer's coordinate space, in pixels)
// and `currentColor` (the sampled pixel) implicitly; the remaining
// arguments are bound by `Shader(function:arguments:)` in the order below.
//
// M5.6: Lambertian diffuse model. The tile wall is treated as the z=0
// plane with surface normal (0, 0, 1). Each pixel's lit contribution from
// a light is `lightColor * lightIntensity * max(0, dot(N, L))`,
// where L is the unit vector from the pixel to the light.
//
// Falloff history: squared in M5.9 ("soft spotlight"), linear in M5.26
// (matching a user-supplied recording), squared again in M16.1, and
// linear again in M16.6 — the definitive Zune client recording shows a
// broad wall-wide wash (quadrant brightness varies only 1.5–2.7x), so the
// linear Lambertian term is the reference behavior.
//
// Tiles are pre-desaturated by SwiftUI's `.saturation(0)` modifier in
// `TileWallView`, so `currentColor` here is grayscale; multiplying by the
// warm/cool light contributions tints the pool while leaving outside
// regions to the gray ambient.
//
// Output rgb is `currentColor.rgb * (ambient + light1.contribution +
// light2.contribution)`, alpha is preserved.
[[stitchable]]
half4 zuneLighting(
    float2  position,
    half4   currentColor,
    float2  panelSize,
    float3  light1Pos,
    float3  light1Color,
    float3  light2Pos,
    float3  light2Color,
    float3  ambientColor,
    float   light1Intensity,
    float   light2Intensity
) {
    // panelSize is unused inside the shader at this point — keyframes are
    // already authored in the same panel-pixel space — but we keep it in
    // the signature so future tuning (e.g. normalized falloff) doesn't
    // require resigning the shader.
    (void)panelSize;

    float3 pixelPos = float3(position.x, position.y, 0.0);
    float3 normal   = float3(0.0, 0.0, 1.0);

    // M5.26: linear Lambertian (exponent 1.0). User supplied a recording of
    // the original Zune client; the wash there is dramatically more diffuse
    // than our cubic spotlight model produced. The whole visible wall is
    // bathed in soft colored light at all times, with smooth gradients
    // rather than tight bright pools surrounded by darkness. Linear
    // Lambertian gives broad coverage: dot=0.5 → 0.50 (was 0.14 cubic);
    // dot=0.2 → 0.20 (was 0.008). Combined with raised ambient and
    // reduced intensity, far pixels still receive meaningful contribution
    // — the "diffused all-over wash" the recording shows.
    //
    // M16.1: back to a squared falloff (exponent 2.0). On the real app
    // window (~1500×950 pt — much smaller than the 2300×1300 reference
    // panel the keyframes were authored for), linear falloff made the two
    // pools overlap into a uniform wash. The user's direction: more focused
    // pools, letting uncovered regions fall dark (ambient stays 0.01).
    // dot=0.5 → 0.25, dot=0.2 → 0.04.
    //
    // M16.6: linear falloff RESTORED (exponent 1.0) — the user supplied a
    // screen recording of the real Zune client, and its lighting is a
    // broad, wall-wide wash: quadrant-mean brightness varies only 1.5–2.7x
    // and every tile stays readable at all times. Squared falloff produced
    // tight pools surrounded by black — the opposite look. Paired with
    // intensity 0.9 / ambient 0.06 (LightingParameters), the simulated
    // multiplier field lands at mean ≈ 0.26–0.31 with gentle gradients,
    // matching the recording's measured stats.
    float3 light1Dir = normalize(light1Pos - pixelPos);
    float  diff1     = max(0.0, dot(normal, light1Dir));
    float3 contrib1  = light1Color * light1Intensity * diff1;

    float3 light2Dir = normalize(light2Pos - pixelPos);
    float  diff2     = max(0.0, dot(normal, light2Dir));
    float3 contrib2  = light2Color * light2Intensity * diff2;

    float3 totalLight = ambientColor + contrib1 + contrib2;

    // M5.19: desaturate `currentColor` INSIDE the shader rather than
    // relying on SwiftUI's `.saturation(0)` modifier composing with
    // `.colorEffect`. The composition isn't reliable — `.colorEffect`
    // can sample the pre-saturation pixel buffer, so source chrominance
    // leaks through to the lit output (visible as "green tile next to
    // brown tile" instead of uniform-hue tiles in the same light pool).
    // Computing luminance here makes the shader the single source of
    // truth for desaturation; the upstream `.saturation(0)` becomes
    // belt-and-braces redundancy that only matters when the shader is
    // disabled (debug no-lighting mode).
    //
    // BT.709 luminance coefficients — perceptually-weighted gray.
    half lumIn = dot(currentColor.rgb, half3(0.2126, 0.7152, 0.0722));
    half3 grayInput = half3(lumIn, lumIn, lumIn);

    half3 lit = grayInput * half3(totalLight);

    return half4(lit, currentColor.a);
}
