#ifndef NPR_EFFECT_TOON_GAUSS_HIER_INCLUDED
#define NPR_EFFECT_TOON_GAUSS_HIER_INCLUDED

// Two-phase NPR effect:
//   Phase 1 — Toon posterisation: quantise colours into discrete bands + saturation.
//   Phase 2 — Hierarchical edge detection: depth (ddx/ddy) + normal discontinuity
//             + Roberts Cross colour gradient, fused with per-layer weights and
//             adaptive dark-area suppression. Optional Gaussian pre-blur on the
//             colour layer. Identical pipeline to Kuwahara+Hier.
// Requires ENABLE_NPR_EDGES + EFFECT_TOON_HIER keywords.

// ── Phase 1: Toon parameters ──────────────────────────────────────────────────
float  _THColorBands;        // discrete colour steps  (2–8)
float  _THPosterizeStrength; // blend posterised vs original  (0–1)
float  _THSaturation;        // saturation scale  (0–3, 1=unchanged)

// ── Phase 2: Hierarchical parameters ─────────────────────────────────────────
float  _THDepthThreshold;    // depth gradient threshold   (0.001–0.2)
float  _THNormalThreshold;   // normal gradient threshold  (0.05–1)
float  _THColorThreshold;    // colour gradient threshold  (0.01–0.5)
float  _THDepthWeight;       // depth layer blend weight   (0–1)
float  _THNormalWeight;      // normal layer blend weight  (0–1)
float  _THColorWeight;       // colour layer blend weight  (0–1)
float  _THEdgeWidth;         // Roberts Cross UV offset    (0.5–10, ×0.001)
float  _THAdaptiveStrength;  // suppress edges in dark areas (0–1)
float  _THHierTightness;     // 0 = soft/wide, 1 = crisp/thin
float  _THHStrength;         // hierarchical edge opacity  (0–1)
float  _THEnableGaussBlur;   // 1 = Gaussian pre-blur on colour samples
float  _THBlurRadius;        // Gaussian blur radius       (0–5, ×0.001)
float  _THCenterWeight;      // Gaussian centre tap weight  (0.1–0.5)
float  _THCardinalWeight;    // Gaussian cardinal tap weight (0–0.3)
float  _THDiagonalWeight;    // Gaussian diagonal tap weight (0–0.1)
float4 _THEdgeColor;         // edge colour

// ── Colour sample helper (point or 9-tap Gaussian) ────────────────────────────
float TH_ColorSample(float2 uv2)
{
    float3 L = float3(0.299, 0.587, 0.114);
    float v;
    if (_THEnableGaussBlur > 0.5)
    {
        float totalW = _THCenterWeight + 4.0*_THCardinalWeight + 4.0*_THDiagonalWeight;
        totalW = max(totalW, 0.0001);
        float cW    = _THCenterWeight   / totalW;
        float cardW = _THCardinalWeight / totalW;
        float diagW = _THDiagonalWeight / totalW;
        float br    = _THBlurRadius * 0.001;
        v  = dot(tex2D(u_BaseColorSampler, uv2).rgb,                               L) * cW;
        v += dot(tex2D(u_BaseColorSampler, uv2 + float2( br,  0)).rgb,             L) * cardW;
        v += dot(tex2D(u_BaseColorSampler, uv2 + float2(-br,  0)).rgb,             L) * cardW;
        v += dot(tex2D(u_BaseColorSampler, uv2 + float2(  0, br)).rgb,             L) * cardW;
        v += dot(tex2D(u_BaseColorSampler, uv2 + float2(  0,-br)).rgb,             L) * cardW;
        v += dot(tex2D(u_BaseColorSampler, uv2 + float2( br, br)).rgb,             L) * diagW;
        v += dot(tex2D(u_BaseColorSampler, uv2 + float2(-br, br)).rgb,             L) * diagW;
        v += dot(tex2D(u_BaseColorSampler, uv2 + float2( br,-br)).rgb,             L) * diagW;
        v += dot(tex2D(u_BaseColorSampler, uv2 + float2(-br,-br)).rgb,             L) * diagW;
    }
    else
    {
        v = dot(tex2D(u_BaseColorSampler, uv2).rgb, L);
    }
    return v;
}

float4 ApplyNPREffect(float4 color, float2 uv, half3 worldNormal, half3 worldViewDir)
{
    // ════════════════════════════════════════════════════════════════════════
    // Phase 1 — Toon posterisation
    // ════════════════════════════════════════════════════════════════════════
    float  bands      = max(2.0, _THColorBands);
    float3 posterized = floor(color.rgb * bands + 0.5) / bands;
    color.rgb = lerp(color.rgb, posterized, _THPosterizeStrength);

    float lumS = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    color.rgb  = lerp(float3(lumS, lumS, lumS), color.rgb, _THSaturation);

    // ════════════════════════════════════════════════════════════════════════
    // Phase 2 — Hierarchical edge detection
    // ════════════════════════════════════════════════════════════════════════
    float depth     = length((float3)worldViewDir);
    float dDepthX   = ddx(depth);
    float dDepthY   = ddy(depth);
    float depthGrad = sqrt(dDepthX*dDepthX + dDepthY*dDepthY);
    float depthLine = smoothstep(_THDepthThreshold - 0.005,
                                 _THDepthThreshold + 0.005, depthGrad);

    float3 dNdx    = ddx((float3)worldNormal);
    float3 dNdy    = ddy((float3)worldNormal);
    float normGrad = sqrt(dot(dNdx, dNdx) + dot(dNdy, dNdy));
    float normLine = smoothstep(_THNormalThreshold - 0.02,
                                _THNormalThreshold + 0.02, normGrad);

    float hoff    = _THEdgeWidth * 0.001;
    float lum_tl  = TH_ColorSample(uv + float2(-hoff,  hoff));
    float lum_tr  = TH_ColorSample(uv + float2( hoff,  hoff));
    float lum_bl  = TH_ColorSample(uv + float2(-hoff, -hoff));
    float lum_br  = TH_ColorSample(uv + float2( hoff, -hoff));
    float colGrad = abs(lum_tl - lum_br) + abs(lum_tr - lum_bl);
    float colLine = smoothstep(_THColorThreshold - 0.01,
                               _THColorThreshold + 0.01, colGrad);

    float brightness = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    float adapt      = lerp(1.0, saturate(brightness * 2.0), _THAdaptiveStrength);
    depthLine *= adapt;
    colLine   *= adapt;
    normLine  *= lerp(1.0, adapt, 0.5);

    float hEdge = max(depthLine * _THDepthWeight,
                  max(normLine  * _THNormalWeight,
                      colLine   * _THColorWeight));
    float hierHW = lerp(0.175, 0.025, _THHierTightness);
    hEdge = smoothstep(0.375 - hierHW, 0.375 + hierHW, hEdge);
    hEdge *= _THHStrength;

    color.rgb = lerp(color.rgb, _THEdgeColor.rgb, hEdge);
    return color;
}

#endif // NPR_EFFECT_TOON_GAUSS_HIER_INCLUDED
