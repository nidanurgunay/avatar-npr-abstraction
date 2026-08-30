#ifndef NPR_EFFECT_TOON_INCLUDED
#define NPR_EFFECT_TOON_INCLUDED

// Cel / toon shading — Technique 9 (keyword EFFECT_TOON).
// Pure colour posterisation only — no edge detection.
// Use the inverted-hull outline pass for silhouette lines,
// or switch to EFFECT_SOBEL / EFFECT_HIERARCHICAL for image-space edges.
// Requires ENABLE_NPR_EDGES + EFFECT_TOON keywords.

float  _ToonColorBands;        // discrete colour steps per channel  (2–8)
float  _ToonPosterizeStrength; // blend posterised vs original        (0–1)
float  _ToonSaturation;        // saturation scale (1=unchanged, 1.5=boosted)

float4 ApplyNPREffect(float4 color, float2 uv, half3 worldNormal, half3 worldViewDir)
{
    // ── 1. Posterisation ──────────────────────────────────────────────────────
    // Posterise first so saturation acts on already-stepped colours.
    float  bands      = max(2.0, _ToonColorBands);
    float3 posterized = floor(color.rgb * bands + 0.5) / bands;
    color.rgb = lerp(color.rgb, posterized, _ToonPosterizeStrength);

    // ── 2. Saturation ─────────────────────────────────────────────────────────
    float lum  = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    color.rgb  = lerp(float3(lum, lum, lum), color.rgb, _ToonSaturation);

    return color;
}

#endif // NPR_EFFECT_TOON_INCLUDED
