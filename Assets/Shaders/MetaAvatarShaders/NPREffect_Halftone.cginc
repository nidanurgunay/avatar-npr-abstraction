#ifndef NPR_EFFECT_HALFTONE_INCLUDED
#define NPR_EFFECT_HALFTONE_INCLUDED

// Halftone dot pattern — adapted from Assets/Shaders/CommonNPRShaders/HalftoneHatching.shader.
// Tone is derived from the luminance of the incoming PBR colour (no separate light pass).
//
// Tone normalisation: dark-albedo materials (skin ≈ 0.5–0.75) never reach luminance=1.0 even
// under full PBR lighting. Without remapping, dotRadius never collapses to zero and dots
// persist on fully-lit highlights. _HTToneWhitePoint defines the expected peak luminance;
// dividing by it stretches [0, whitePoint] → [0, 1] so the brightest pixel → tone=1.0 (pure paper).
//
// Visibility suppression: when dotRadius → 0, smoothstep(−ε, +ε, 0) = 0.5 — a faint ink
// ghost appears at each grid centre even in fully-lit cells. The visibility ramp drives
// pattern to 0 before dotRadius reaches that degenerate range, eliminating the artefact.
//
// Requires ENABLE_NPR_EDGES + EFFECT_HALFTONE keywords.

float  _HTScale;            // dot grid frequency       (2–100)
float  _HTSharpness;        // dot edge sharpness       (1–50)
float  _HTAngle;            // grid rotation in degrees (0–90)
float  _HTToneBias;         // additive tone offset     (-0.5–0.5)
float  _HTBrightCutoff;     // shadow threshold: 0=everywhere, 0.4=shadow only (0–0.95)
float  _HTToneWhitePoint;   // peak luminance → tone=1.0 (0.1–1.0, default 0.75)
float4 _HTInkColor;         // ink / dot colour
float4 _HTPaperColor;       // paper / background colour
float  _HTTextureInfluence; // 0=flat ink/paper, 1=tint with original PBR colour (0–1)
float  _HTStrength;         // blend pattern over original PBR colour (0–1)

// ── Helpers ───────────────────────────────────────────────────────────────────
float2 HT_Rotate2D(float2 p, float deg)
{
    float rad = deg * 0.01745329251f;
    float c = cos(rad), s = sin(rad);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Returns 0 (paper) → 1 (ink). Darker tone → larger dot radius.
// dotRadius = sqrt(1 - tone) * 0.5 matches the working standalone shader directly.
// _HTToneWhitePoint normalisation already maps peak PBR luminance → tone=1.0,
// so bright pixels collapse dotRadius to 0 naturally without a separate cutoff remap.
float HT_HalftonePattern(float2 coords, float tone)
{
    float2 rotated   = HT_Rotate2D(coords, _HTAngle);
    float2 gridPos   = frac(rotated * _HTScale) - 0.5;
    float  dist      = length(gridPos);

    float  t         = max(0.0, 1.0 - tone);
    float  dotRadius = sqrt(t) * 0.5;
    float  sharpInv  = 0.5 / max(_HTSharpness, 0.001);

    // Visibility ramp: suppress dot before dotRadius crosses the degenerate
    // smoothstep range (straddles 0 → leaks 0.5 ink at grid centres).
    float visibility = smoothstep(0.0, sharpInv * 2.0, dotRadius);
    return (1.0 - smoothstep(dotRadius - sharpInv, dotRadius + sharpInv, dist)) * visibility;
}

float4 ApplyNPREffect(float4 color, float2 uv, half3 worldNormal, half3 worldViewDir)
{
    float lum = dot(color.rgb, float3(0.299, 0.587, 0.114));

    // Tone normalisation: map [0, _HTToneWhitePoint] → [0, 1].
    // Without this, dark-albedo materials never collapse dotRadius to zero
    // and dots appear even on fully-lit highlights.
    float tone = saturate(lum / max(_HTToneWhitePoint, 0.001) + _HTToneBias);

    float pattern = HT_HalftonePattern(uv, tone);

    // _HTBrightCutoff: suppress pattern in well-lit hatch-free zone
    pattern *= 1.0 - smoothstep(_HTBrightCutoff - 0.05, _HTBrightCutoff + 0.05, tone);

    float3 paperCol     = lerp(_HTPaperColor.rgb, color.rgb,                   _HTTextureInfluence);
    float3 inkCol       = lerp(_HTInkColor.rgb,   color.rgb * _HTInkColor.rgb, _HTTextureInfluence);
    float3 patternColor = lerp(paperCol, inkCol, pattern);

    color.rgb = lerp(color.rgb, patternColor, _HTStrength);
    return color;
}

#endif // NPR_EFFECT_HALFTONE_INCLUDED
