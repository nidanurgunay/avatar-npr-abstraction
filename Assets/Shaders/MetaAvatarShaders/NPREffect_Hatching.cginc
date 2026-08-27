#ifndef NPR_EFFECT_HATCHING_INCLUDED
#define NPR_EFFECT_HATCHING_INCLUDED

// Tonal Art Map hatching — adapted from Assets/Shaders/CommonNPRShaders/HalftoneHatching.shader.
// Based on Praun et al. "Real-Time Hatching" (SIGGRAPH 2001).
//
// Tone normalisation: _HatToneWhitePoint maps peak PBR luminance → tone = 1.0 (pure paper),
// ensuring bright pixels naturally produce t = 0 with no pattern.
//
// Layer thresholds are absolute values matching the working standalone shader:
//   Layer 1 (primary)   : t > 0.15, ramps to 0.40
//   Layer 2 (cross)     : t > 0.35, ramps to 0.60
//   Layer 3 (dense diag): t > 0.55, ramps to 0.80
//   Layer 4 (fill)      : t > 0.80, ramps to 1.00
// This spreads progressive layering across the full tonal range rather than
// compressing it into a narrow shadow zone.
//
// Requires ENABLE_NPR_EDGES + EFFECT_HATCHING keywords.

float  _HatScale;            // line/cell frequency       (1–100)
float  _HatAngle;            // primary hatch angle°      (0–180)
float  _HatCrossAngle;       // cross-hatch angle°        (0–180)
float  _HatThickness;        // line thickness            (0.01–0.5)
float  _HatToneBias;         // additive tone offset      (-0.5–0.5)
float  _HatBrightCutoff;     // shadow threshold: 0=everywhere, 0.4=shadow only (0–0.95)
float  _HatToneWhitePoint;   // peak luminance → tone=1.0 (0.1–1.0, default 0.75)
float  _HatToneLevels;       // TAM column count          (2–8,     default 6)
float4 _HatInkColor;         // ink / line colour
float4 _HatPaperColor;       // paper / background colour
float  _HatTextureInfluence; // 0=flat, 1=tint with original PBR colour (0–1)
float  _HatStrength;         // blend pattern over original PBR colour  (0–1)

// ── Helpers ───────────────────────────────────────────────────────────────────
float2 Hat_Rotate2D(float2 p, float deg)
{
    float rad = deg * 0.01745329251f;
    float c = cos(rad), s = sin(rad);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Returns 0 (gap) → 1 (on-line). Rotates coords and scans along X.
float Hat_HatchLine(float2 coords, float angleDeg, float thickness)
{
    float2 rotated = Hat_Rotate2D(coords, angleDeg);
    float  linePos = frac(rotated.x * _HatScale);
    float  mask    = smoothstep(thickness, thickness + 0.02, abs(linePos - 0.5));
    return 1.0 - mask;
}

// TAM: layers activate progressively as darkness t = 1 − tone increases.
// Absolute thresholds (0.15 / 0.35 / 0.55 / 0.80) match the working standalone shader.
float Hat_HatchingPattern(float2 coords, float tone)
{
    float t = 1.0 - tone; // darkness: 0=fully lit, 1=fully dark
    float pattern = 0.0;

    // Layer 1 — primary direction (moderate shadow)
    if (t > 0.15)
        pattern = max(pattern,
            Hat_HatchLine(coords, _HatAngle, _HatThickness)
            * smoothstep(0.15, 0.40, t));

    // Layer 2 — cross hatch (deeper shadow)
    if (t > 0.35)
        pattern = max(pattern,
            Hat_HatchLine(coords, _HatCrossAngle, _HatThickness)
            * smoothstep(0.35, 0.60, t));

    // Layer 3 — dense diagonal (very dark)
    if (t > 0.55)
    {
        float denseAngle = (_HatAngle + _HatCrossAngle) * 0.5;
        pattern = max(pattern,
            Hat_HatchLine(coords, denseAngle, _HatThickness * 1.5)
            * smoothstep(0.55, 0.80, t));
    }

    // Layer 4 — near-black fill
    if (t > 0.80)
        pattern = max(pattern, smoothstep(0.80, 1.0, t));

    return pattern;
}

float4 ApplyNPREffect(float4 color, float2 uv, half3 worldNormal, half3 worldViewDir)
{
    float lum = dot(color.rgb, float3(0.299, 0.587, 0.114));

    // Tone normalisation: map [0, _HatToneWhitePoint] → [0, 1].
    // Without this, dark-albedo materials never reach tone=1.0 under PBR lighting
    // and permanently show Layer 1 marks even on fully-lit highlights.
    float tone = saturate(lum / max(_HatToneWhitePoint, 0.001) + _HatToneBias);

    float pattern = Hat_HatchingPattern(uv, tone);

    // _HatBrightCutoff: suppress pattern in well-lit hatch-free zone
    pattern *= 1.0 - smoothstep(_HatBrightCutoff - 0.05, _HatBrightCutoff + 0.05, tone);

    float3 paperCol     = lerp(_HatPaperColor.rgb, color.rgb,                    _HatTextureInfluence);
    float3 inkCol       = lerp(_HatInkColor.rgb,   color.rgb * _HatInkColor.rgb, _HatTextureInfluence);
    float3 patternColor = lerp(paperCol, inkCol, pattern);

    color.rgb = lerp(color.rgb, patternColor, _HatStrength);
    return color;
}

#endif // NPR_EFFECT_HATCHING_INCLUDED
