#ifndef NPR_EFFECT_KUWAHARA2_GAUSS_HIER_INCLUDED
#define NPR_EFFECT_KUWAHARA2_GAUSS_HIER_INCLUDED

// Two-phase NPR effect:
//   Phase 1 — Anisotropic Kuwahara (Technique 10 / K2):
//             Structure-tensor-guided 8-sector elliptical filter.  Same algorithm
//             as Technique 8 (standalone K2) — see NPREffect_Kuwahara2.cginc.
//   Phase 2 — Hierarchical edge detection:
//             Depth (camera-distance ddx/ddy) + normal discontinuity + Roberts Cross
//             colour gradient, fused with per-layer weights and adaptive dark-area
//             suppression.  Colour layer supports optional Gaussian pre-blur.
//             Same pipeline as Technique 8 (K+Hier) — see NPREffect_KuwaharaGaussHier.cginc.
// Requires ENABLE_NPR_EDGES + EFFECT_KUWAHARA2_HIER keywords.

// ── Phase 1: Anisotropic Kuwahara parameters ──────────────────────────────────
float _K2HKuwRadius;    // Ellipse radius, UV-space  (0.5–8,    ×0.001)
float _K2HKuwStrength;  // Kuwahara blend             (0–1)
float _K2HKuwAlpha;     // Eccentricity α             (0.5–3)
float _K2HKuwQ;         // Weight sharpness q         (1–16)
float _K2HKuwTau;       // Std-deviation floor τ      (0.001–0.1)

// ── Phase 2: Hierarchical parameters ─────────────────────────────────────────
float  _K2HDepthThreshold;    // Depth gradient threshold   (0.001–0.2)
float  _K2HNormalThreshold;   // Normal gradient threshold  (0.05–1)
float  _K2HColorThreshold;    // Colour gradient threshold  (0.01–0.5)
float  _K2HDepthWeight;       // Depth layer blend weight   (0–1)
float  _K2HNormalWeight;      // Normal layer blend weight  (0–1)
float  _K2HColorWeight;       // Colour layer blend weight  (0–1)
float  _K2HEdgeWidth;         // Roberts Cross UV offset    (0.5–10, ×0.001)
float  _K2HAdaptiveStrength;  // Suppress edges in dark areas (0–1)
float  _K2HHierTightness;     // 0 = soft/wide, 1 = crisp/thin
float  _K2HHStrength;         // Hierarchical edge opacity  (0–1)
float  _K2HEnableGaussBlur;   // 1 = Gaussian pre-blur on colour samples
float  _K2HBlurRadius;        // Gaussian blur radius       (0–5, ×0.001)
float  _K2HCenterWeight;      // Gaussian centre tap weight  (0.1–0.5)
float  _K2HCardinalWeight;    // Gaussian cardinal tap weight (0–0.3)
float  _K2HDiagonalWeight;    // Gaussian diagonal tap weight (0–0.1)
float4 _K2HEdgeColor;         // Edge colour

// ── Shared K2 helpers ─────────────────────────────────────────────────────────
static const float2 K2H_DIRS[8] = {
    float2( 1.0000,  0.0000),
    float2( 0.7071,  0.7071),
    float2( 0.0000,  1.0000),
    float2(-0.7071,  0.7071),
    float2(-1.0000,  0.0000),
    float2(-0.7071, -0.7071),
    float2( 0.0000, -1.0000),
    float2( 0.7071, -0.7071),
};

void K2H_Sector(float2 uv2, float2 dir, float2 mrow0, float2 mrow1, float3 cc,
                out float3 mean, out float sig)
{
    float3 s1 = tex2D(u_BaseColorSampler, uv2 + float2(dot(mrow0, dir*0.45), dot(mrow1, dir*0.45))).rgb;
    float3 s2 = tex2D(u_BaseColorSampler, uv2 + float2(dot(mrow0, dir*0.75), dot(mrow1, dir*0.75))).rgb;
    float3 s3 = tex2D(u_BaseColorSampler, uv2 + float2(dot(mrow0, dir      ), dot(mrow1, dir      ))).rgb;
    mean = cc*0.40 + s1*0.28 + s2*0.20 + s3*0.12;
    float v = dot(cc-mean, cc-mean)*0.40 + dot(s1-mean, s1-mean)*0.28
            + dot(s2-mean, s2-mean)*0.20 + dot(s3-mean, s3-mean)*0.12;
    sig = sqrt(max(v, 0.0));
}

// Colour sample for Hierarchical layer — point or 9-tap Gaussian pre-blur.
float K2H_ColorSample(float2 uv2)
{
    float3 L = float3(0.299, 0.587, 0.114);
    float v;
    if (_K2HEnableGaussBlur > 0.5)
    {
        float totalW = _K2HCenterWeight + 4.0*_K2HCardinalWeight + 4.0*_K2HDiagonalWeight;
        totalW = max(totalW, 0.0001);
        float cW    = _K2HCenterWeight   / totalW;
        float cardW = _K2HCardinalWeight / totalW;
        float diagW = _K2HDiagonalWeight / totalW;
        float br    = _K2HBlurRadius * 0.001;
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
    // Phase 1 — Anisotropic Kuwahara
    // ════════════════════════════════════════════════════════════════════════
    float lum = dot(color.rgb, float3(0.299, 0.587, 0.114));
    float gx  = ddx(lum);
    float gy  = ddy(lum);
    float E   = gx*gx,  F = gx*gy,  G = gy*gy;

    float disc = sqrt(max(0.0, (E-G)*(E-G) + 4.0*F*F));
    float lam1 = (E+G+disc)*0.5,  lam2 = (E+G-disc)*0.5;
    float phi  = 0.5 * atan2(2.0*F, E - G + 1e-7) + 1.5707963;
    float A    = saturate((lam1 - lam2) / (lam1 + lam2 + 1e-7));

    float r     = _K2HKuwRadius * 0.001;
    float alpha = max(_K2HKuwAlpha, 0.1);
    float ea    = (alpha + A) / alpha * r;
    float eb    = alpha / (alpha + A) * r;
    float cp    = cos(phi),  sp = sin(phi);
    float2 mr0  = float2(ea*cp,  eb*sp);
    float2 mr1  = float2(-ea*sp, eb*cp);

    float3 cc = tex2D(u_BaseColorSampler, uv).rgb;

    float3 m0,m1,m2,m3,m4,m5,m6,m7;
    float  sv0,sv1,sv2,sv3,sv4,sv5,sv6,sv7;
    K2H_Sector(uv, K2H_DIRS[0], mr0, mr1, cc, m0, sv0);
    K2H_Sector(uv, K2H_DIRS[1], mr0, mr1, cc, m1, sv1);
    K2H_Sector(uv, K2H_DIRS[2], mr0, mr1, cc, m2, sv2);
    K2H_Sector(uv, K2H_DIRS[3], mr0, mr1, cc, m3, sv3);
    K2H_Sector(uv, K2H_DIRS[4], mr0, mr1, cc, m4, sv4);
    K2H_Sector(uv, K2H_DIRS[5], mr0, mr1, cc, m5, sv5);
    K2H_Sector(uv, K2H_DIRS[6], mr0, mr1, cc, m6, sv6);
    K2H_Sector(uv, K2H_DIRS[7], mr0, mr1, cc, m7, sv7);

    float tau = _K2HKuwTau,  q = _K2HKuwQ;
    float w0=1.0/pow(max(tau,sv0),q), w1=1.0/pow(max(tau,sv1),q);
    float w2=1.0/pow(max(tau,sv2),q), w3=1.0/pow(max(tau,sv3),q);
    float w4=1.0/pow(max(tau,sv4),q), w5=1.0/pow(max(tau,sv5),q);
    float w6=1.0/pow(max(tau,sv6),q), w7=1.0/pow(max(tau,sv7),q);
    float wsum = w0+w1+w2+w3+w4+w5+w6+w7;
    float3 kResult = (m0*w0+m1*w1+m2*w2+m3*w3+m4*w4+m5*w5+m6*w6+m7*w7) / max(wsum,1e-7);

    color.rgb = lerp(color.rgb, kResult, _K2HKuwStrength);

    // ════════════════════════════════════════════════════════════════════════
    // Phase 2 — Hierarchical edge detection
    // ════════════════════════════════════════════════════════════════════════
    float depth     = length((float3)worldViewDir);
    float dDepthX   = ddx(depth);
    float dDepthY   = ddy(depth);
    float depthGrad = sqrt(dDepthX*dDepthX + dDepthY*dDepthY);
    float depthLine = smoothstep(_K2HDepthThreshold - 0.005,
                                 _K2HDepthThreshold + 0.005, depthGrad);

    float3 dNdx    = ddx((float3)worldNormal);
    float3 dNdy    = ddy((float3)worldNormal);
    float normGrad = sqrt(dot(dNdx, dNdx) + dot(dNdy, dNdy));
    float normLine = smoothstep(_K2HNormalThreshold - 0.02,
                                _K2HNormalThreshold + 0.02, normGrad);

    float hoff    = _K2HEdgeWidth * 0.001;
    float lum_tl  = K2H_ColorSample(uv + float2(-hoff,  hoff));
    float lum_tr  = K2H_ColorSample(uv + float2( hoff,  hoff));
    float lum_bl  = K2H_ColorSample(uv + float2(-hoff, -hoff));
    float lum_br  = K2H_ColorSample(uv + float2( hoff, -hoff));
    float colGrad = abs(lum_tl - lum_br) + abs(lum_tr - lum_bl);
    float colLine = smoothstep(_K2HColorThreshold - 0.01,
                               _K2HColorThreshold + 0.01, colGrad);

    float brightness = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    float adapt      = lerp(1.0, saturate(brightness * 2.0), _K2HAdaptiveStrength);
    depthLine *= adapt;
    colLine   *= adapt;
    normLine  *= lerp(1.0, adapt, 0.5);

    float hEdge = max(depthLine * _K2HDepthWeight,
                  max(normLine  * _K2HNormalWeight,
                      colLine   * _K2HColorWeight));
    float hierHW = lerp(0.175, 0.025, _K2HHierTightness);
    hEdge = smoothstep(0.375 - hierHW, 0.375 + hierHW, hEdge);
    hEdge *= _K2HHStrength;

    color.rgb = lerp(color.rgb, _K2HEdgeColor.rgb, hEdge);
    return color;
}

#endif // NPR_EFFECT_KUWAHARA2_GAUSS_HIER_INCLUDED
