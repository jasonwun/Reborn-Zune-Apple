#include <metal_stdlib>
using namespace metal;

// Two-point-light + ambient color-effect shader. SwiftUI's `.colorEffect`
// modifier passes `position` (in the layer's coordinate space, in pixels)
// and `currentColor` (the sampled pixel) implicitly; the remaining
// arguments are bound by `Shader(function:arguments:)` in the order below.
//
// Falloff: `1 / (1 + d² * attenuationScale)`. This simplification of the
// XAML PointLight's `1 / (constant + linear*d + quadratic*d²)` keeps the
// scene from washing out at typical 1920x1080 panel sizes while still
// producing the warm/cool gradient the original is famous for.
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
    float   light2Intensity,
    float   attenuationScale
) {
    // Treat the surface as the z=0 plane in the lights' coordinate space.
    // panelSize is unused inside the shader at this point — keyframes are
    // already authored in the same panel-pixel space — but we keep it in
    // the signature so future tuning (e.g. normalized falloff) doesn't
    // require resigning the shader.
    (void)panelSize;

    float3 pixelPos = float3(position.x, position.y, 0.0);

    float3 toLight1 = pixelPos - light1Pos;
    float  d1Sq    = dot(toLight1, toLight1);
    float  falloff1 = 1.0 / (1.0 + d1Sq * attenuationScale);
    float3 contrib1 = light1Color * light1Intensity * falloff1;

    float3 toLight2 = pixelPos - light2Pos;
    float  d2Sq    = dot(toLight2, toLight2);
    float  falloff2 = 1.0 / (1.0 + d2Sq * attenuationScale);
    float3 contrib2 = light2Color * light2Intensity * falloff2;

    float3 totalLight = ambientColor + contrib1 + contrib2;

    float3 base = float3(currentColor.rgb);
    float3 lit  = base * totalLight;

    return half4(half3(lit), currentColor.a);
}
