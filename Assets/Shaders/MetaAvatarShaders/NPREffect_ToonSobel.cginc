#ifndef NPR_EFFECT_TOON_SOBEL_INCLUDED
#define NPR_EFFECT_TOON_SOBEL_INCLUDED

// Two-phase NPR effect:
//   Phase 1 — Toon posterisation: quantise colours into discrete bands + saturation.
//   Phase 2 — Gaussian Sobel edge detection: identical pipeline to Kuwahara+Sobel
//             (optional 9-tap Gaussian pre-blur, threshold band, 4x progressive
//             smoothstep, power curve). Edge colour taken from _InnerLineColor.
// Requires ENABLE_NPR_EDGES + EFFECT_TOON_SOBEL keywords.

// ── Phase 1: Toon parameters ──────────────────────────────────────────────────
float _TSColorBands;        // discrete colour steps  (2–8)
float _TSPosterizeStrength; // blend posterised vs original  (0–1)
float _TSSaturation;        // saturation scale  (0–3, 1=unchanged)

// ── Phase 2: Gaussian Sobel parameters ───────────────────────────────────────
float4 _InnerLineColor;       // shared edge colour (set in UI "Line Color" row)
float  _TSEnableGaussBlur;    // 1 = 9-tap Gaussian pre-blur, 0 = point sample
float  _TSSobelSampleDist;    // Sobel kernel UV offset     (0–10, ×0.001)
float  _TSBlurRadius;         // per-sample Gaussian radius (0–5,  ×0.001)
float  _TSCenterWeight;       // Gaussian centre tap weight  (0.1–0.5)
float  _TSCardinalWeight;     // Gaussian cardinal tap weight (0–0.3)
float  _TSDiagonalWeight;     // Gaussian diagonal tap weight (0–0.1)
float  _TSThreshold;          // Sobel threshold base  (0–0.5)
float  _TSThreshMin;          // lower multiplier  (0–1)
float  _TSThreshMax;          // upper multiplier  (1–5)
float  _TSTightness;          // 0 = soft/wide, 1 = crisp/thin
float  _TSPowerCurve;         // post-pass power curve  (0.5–5)
float  _TSSobelStrength;      // edge opacity  (0–1)

// ── Gaussian luma helper ──────────────────────────────────────────────────────
float TS_GaussLuma(float2 center, float blurR, float cW, float cardW, float diagW)
{
    float3 L = float3(0.299, 0.587, 0.114);
    float v = 0.0;
    v += dot(tex2D(u_BaseColorSampler, center).rgb,                               L) * cW;
    v += dot(tex2D(u_BaseColorSampler, center + float2( blurR,     0)).rgb,       L) * cardW;
    v += dot(tex2D(u_BaseColorSampler, center + float2(-blurR,     0)).rgb,       L) * cardW;
    v += dot(tex2D(u_BaseColorSampler, center + float2(     0,  blurR)).rgb,      L) * cardW;
    v += dot(tex2D(u_BaseColorSampler, center + float2(     0, -blurR)).rgb,      L) * cardW;
    v += dot(tex2D(u_BaseColorSampler, center + float2( blurR,  blurR)).rgb,      L) * diagW;
    v += dot(tex2D(u_BaseColorSampler, center + float2(-blurR,  blurR)).rgb,      L) * diagW;
    v += dot(tex2D(u_BaseColorSampler, center + float2( blurR, -blurR)).rgb,      L) * diagW;
    v += dot(tex2D(u_BaseColorSampler, center + float2(-blurR, -blurR)).rgb,      L) * diagW;
    return v;
}

float4 ApplyNPREffect(float4 color, float2 uv, half3 worldNormal, half3 worldViewDir)
{
    // ════════════════════════════════════════════════════════════════════════
    // Phase 1 — Toon posterisation
    // ════════════════════════════════════════════════════════════════════════
    float  bands      = max(2.0, _TSColorBands);
    float3 posterized = floor(color.rgb * bands + 0.5) / bands;
    color.rgb = lerp(color.rgb, posterized, _TSPosterizeStrength);

    float lumS = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    color.rgb  = lerp(float3(lumS, lumS, lumS), color.rgb, _TSSaturation);

    // ════════════════════════════════════════════════════════════════════════
    // Phase 2 — Gaussian Sobel edge detection
    // ════════════════════════════════════════════════════════════════════════
    float off  = _TSSobelSampleDist * 0.001;
    float blur = _TSBlurRadius      * 0.001;

    float cW, cardW, diagW;
    if (_TSEnableGaussBlur > 0.5)
    {
        float totalW = _TSCenterWeight + 4.0*_TSCardinalWeight + 4.0*_TSDiagonalWeight;
        totalW = max(totalW, 0.0001);
        cW    = _TSCenterWeight   / totalW;
        cardW = _TSCardinalWeight / totalW;
        diagW = _TSDiagonalWeight / totalW;
    }
    else { cW = 1.0; cardW = 0.0; diagW = 0.0; }

    float tl = TS_GaussLuma(uv + float2(-off,  off), blur, cW, cardW, diagW);
    float t  = TS_GaussLuma(uv + float2(   0,  off), blur, cW, cardW, diagW);
    float tr = TS_GaussLuma(uv + float2( off,  off), blur, cW, cardW, diagW);
    float l  = TS_GaussLuma(uv + float2(-off,    0), blur, cW, cardW, diagW);
    float ri = TS_GaussLuma(uv + float2( off,    0), blur, cW, cardW, diagW);
    float bl = TS_GaussLuma(uv + float2(-off, -off), blur, cW, cardW, diagW);
    float b  = TS_GaussLuma(uv + float2(   0, -off), blur, cW, cardW, diagW);
    float br = TS_GaussLuma(uv + float2( off, -off), blur, cW, cardW, diagW);

    float sobelX  = (tr + 2.0*ri + br) - (tl + 2.0*l  + bl);
    float sobelY  = (tl + 2.0*t  + tr) - (bl + 2.0*b  + br);
    float edgeMag = sqrt(sobelX*sobelX + sobelY*sobelY);

    float minEdge = _TSThreshold * _TSThreshMin;
    float maxEdge = _TSThreshold * _TSThreshMax;
    float edge    = smoothstep(minEdge, maxEdge, edgeMag);

    float hw1 = lerp(0.5, 0.03, _TSTightness);
    edge = smoothstep(0.5 - hw1, 0.5 + hw1, edge);
    float hw2 = lerp(0.5, 0.15, _TSTightness);
    edge = smoothstep(0.5 - hw2, 0.5 + hw2, edge);
    float hw3 = lerp(0.5, 0.25, _TSTightness);
    edge = smoothstep(0.5 - hw3, 0.5 + hw3, edge);
    float hw4 = lerp(0.5, 0.35, _TSTightness);
    edge = smoothstep(0.5 - hw4, 0.5 + hw4, edge);

    edge = pow(edge, _TSPowerCurve);
    edge *= _TSSobelStrength;

    color.rgb = lerp(color.rgb, _InnerLineColor.rgb, edge);
    return color;
}

#endif // NPR_EFFECT_TOON_SOBEL_INCLUDED
