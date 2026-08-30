#ifndef NPR_EFFECT_HIERARCHICAL_INCLUDED
#define NPR_EFFECT_HIERARCHICAL_INCLUDED

// Hierarchical multi-layer edge detection — AHEAD-aligned implementation.
// Three layers fused with weighted max-pooling:
//   Layer 1  Depth proxy  — ddx/ddy on camera distance  → silhouette edges
//   Layer 2  Normal       — ddx/ddy on world normal      → surface crease edges
//   Layer 3  XDoG         — Difference of Gaussians with tanh → texture/ink edges
// Adaptive gain (inverse-linear AGC) applied to normal layer only (AHEAD §2.5).
// Requires ENABLE_NPR_EDGES + EFFECT_HIERARCHICAL keywords.

float4 _HEdgeColor;
float  _HDepthThreshold;     // depth gradient threshold   (0.001–0.2)
float  _HNormalThreshold;    // normal gradient threshold  (0.05–1.0)
float  _HColorThreshold;     // (legacy, kept for material compat)
float  _HDepthWeight;        // depth layer blend weight   (0–1)
float  _HDepthScale;         // depth gradient amplifier — clip-plane sensitivity (1–100)
float  _HNormalWeight;       // normal layer blend weight  (0–1)
float  _HColorWeight;        // colour layer blend weight  (0–1)
float  _HEdgeWidth;          // (legacy, kept for material compat)
float  _HAdaptiveStrength;   // adaptive gain blend        (0–1)
float  _HEnableGaussBlur;    // (legacy, kept for material compat)
float  _HBlurRadius;         // fine Gaussian radius σ     (0–5, × 0.001)
float  _HCenterWeight;       // Gaussian centre tap weight  (0.1–0.5)
float  _HCardinalWeight;     // Gaussian cardinal tap weight (0–0.3)
float  _HDiagonalWeight;     // Gaussian diagonal tap weight (0–0.1)
float  _HXDoGK;              // XDoG coarse/fine radius ratio k  (default 1.6)
float  _HXDoGTau;            // XDoG subtraction factor τ        (default 0.98)
float  _HXDoGPhi;            // XDoG tanh sharpness φ            (default 10.0)
float  _HEnableSkinDiscard;  // 1 = suppress colour edges on skin pixels
float  _HSkinHueMin;         // skin hue lower bound  (default 0.02)
float  _HSkinHueMax;         // skin hue upper bound  (default 0.12)
float  _HSkinSatMin;         // skin saturation minimum (default 0.15)

float3 RGBtoHSV_H(float3 c) {
    float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float  d = q.x - min(q.w, q.y);
    float  e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0*d + e)), d / (q.x + e), q.x);
}

// 9-tap Gaussian-weighted luminance centred at uv with configurable radius.
float HGaussianLuma(float2 uv, float br, float cW, float cardW, float diagW)
{
    float3 L = float3(0.2126, 0.7152, 0.0722);
    float v  = dot(tex2D(u_BaseColorSampler, uv).rgb,                         L) * cW;
    v += dot(tex2D(u_BaseColorSampler, uv + float2( br,  0)).rgb,             L) * cardW;
    v += dot(tex2D(u_BaseColorSampler, uv + float2(-br,  0)).rgb,             L) * cardW;
    v += dot(tex2D(u_BaseColorSampler, uv + float2(  0, br)).rgb,             L) * cardW;
    v += dot(tex2D(u_BaseColorSampler, uv + float2(  0,-br)).rgb,             L) * cardW;
    v += dot(tex2D(u_BaseColorSampler, uv + float2( br, br)).rgb,             L) * diagW;
    v += dot(tex2D(u_BaseColorSampler, uv + float2(-br, br)).rgb,             L) * diagW;
    v += dot(tex2D(u_BaseColorSampler, uv + float2( br,-br)).rgb,             L) * diagW;
    v += dot(tex2D(u_BaseColorSampler, uv + float2(-br,-br)).rgb,             L) * diagW;
    return v;
}

// worldPos: actual world-space position of the fragment (needed for correct depth).
float4 ApplyNPREffect(float4 color, float2 uv, half3 worldNormal, half3 worldViewDir, float3 worldPos)
{
    // ── Layer 1: depth proxy (perspective-normalised distance gradient) ──────
    float depth     = length(worldPos - (float3)_WorldSpaceCameraPos);
    float dDepthX   = ddx(depth);
    float dDepthY   = ddy(depth);
    float depthGrad = sqrt(dDepthX*dDepthX + dDepthY*dDepthY) / max(depth, 0.01) * _HDepthScale;
    float depthLine = smoothstep(_HDepthThreshold - 0.005,
                                 _HDepthThreshold + 0.005, depthGrad);

    // ── Layer 2: normal discontinuity ────────────────────────────────────────
    float3 dNdx     = ddx((float3)worldNormal);
    float3 dNdy     = ddy((float3)worldNormal);
    float  normGrad = sqrt(dot(dNdx, dNdx) + dot(dNdy, dNdy));
    float  normLine = smoothstep(_HNormalThreshold - 0.02,
                                 _HNormalThreshold + 0.02, normGrad);

    // ── Layer 3: XDoG texture edge (Difference of Gaussians) ─────────────────
    // Replaces Roberts Cross. Fires only where fine Gaussian sees detail
    // that coarse Gaussian misses — no phantom halo edges at low threshold.
    float totalW = _HCenterWeight + 4.0*_HCardinalWeight + 4.0*_HDiagonalWeight;
    totalW = max(totalW, 0.0001);
    float cW    = _HCenterWeight   / totalW;
    float cardW = _HCardinalWeight / totalW;
    float diagW = _HDiagonalWeight / totalW;

    float sigma1 = _HBlurRadius * 0.001;
    float sigma2 = _HBlurRadius * _HXDoGK * 0.001;
    float g1 = HGaussianLuma(uv, sigma1, cW, cardW, diagW);
    float g2 = HGaussianLuma(uv, sigma2, cW, cardW, diagW);
    float D  = g1 - _HXDoGTau * g2;
    float colLine = D < -_HColorThreshold
        ? saturate(-tanh(_HXDoGPhi * (D + _HColorThreshold)))
        : 0.0;

    if (_HEnableSkinDiscard > 0.5) {
        float3 ctr = tex2D(u_BaseColorSampler, uv).rgb;
        float3 hsv = RGBtoHSV_H(ctr);
        if (hsv.x >= _HSkinHueMin && hsv.x <= _HSkinHueMax && hsv.y >= _HSkinSatMin)
            colLine = 0.0;
    }

    // ── AHEAD adaptive gain — inverse-linear AGC, normal layer only (§2.5) ───
    float luma  = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    float adapt = min(1.0 / (3.0 * luma + 0.1), 4.0);
    adapt = lerp(1.0, adapt, _HAdaptiveStrength);
    normLine *= adapt;

    // ── Weighted max-pooling fusion ───────────────────────────────────────────
    float edge = max(depthLine * _HDepthWeight,
                 max(normLine  * _HNormalWeight,
                     colLine   * _HColorWeight));
    edge = smoothstep(0.20, 0.55, edge);

    color.rgb = lerp(color.rgb, _HEdgeColor.rgb, edge);
    return color;
}

#endif // NPR_EFFECT_HIERARCHICAL_INCLUDED
