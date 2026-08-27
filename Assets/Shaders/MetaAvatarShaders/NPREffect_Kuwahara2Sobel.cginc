#ifndef NPR_EFFECT_KUWAHARA2_SOBEL_INCLUDED
#define NPR_EFFECT_KUWAHARA2_SOBEL_INCLUDED

// Two-phase NPR effect:
//   Phase 1 — Anisotropic Kuwahara (Technique 9 / K2):
//             Structure-tensor-guided 8-sector elliptical filter.  Same algorithm
//             as Technique 8 (standalone K2) — see NPREffect_Kuwahara2.cginc.
//   Phase 2 — Gaussian Sobel (full pipeline):
//             Optional configurable-weight 9-tap Gaussian pre-blur at each of 8
//             Sobel sample positions; threshold band → 4× progressive smoothstep
//             → power curve → opacity.  Same pipeline as Technique 7 (K+Sobel).
// Requires ENABLE_NPR_EDGES + EFFECT_KUWAHARA2_SOBEL keywords.

// ── Phase 1: Anisotropic Kuwahara parameters ──────────────────────────────────
float _K2SKuwRadius;    // Ellipse radius, UV-space  (0.5–8,    ×0.001)
float _K2SKuwStrength;  // Kuwahara blend             (0–1)
float _K2SKuwAlpha;     // Eccentricity α             (0.5–3)
float _K2SKuwQ;         // Weight sharpness q         (1–16)
float _K2SKuwTau;       // Variance floor τ           (0.001–0.1)

// ── Phase 2: Gaussian Sobel parameters ────────────────────────────────────────
float4 _InnerLineColor;
float  _K2SEnableGaussBlur;   // 1 = 9-tap Gaussian pre-blur, 0 = point sample
float  _K2SSobelSampleDist;   // Sobel kernel UV offset  (0–10, ×0.001)
float  _K2SBlurRadius;        // Per-sample Gaussian blur radius (0–5, ×0.001)
float  _K2SCenterWeight;      // Gaussian center tap weight   (0.1–0.5)
float  _K2SCardinalWeight;    // Gaussian cardinal tap weight (0–0.3)
float  _K2SDiagonalWeight;    // Gaussian diagonal tap weight (0–0.1)
float  _K2SThreshold;         // Sobel threshold base   (0–0.5)
float  _K2SThreshMin;         // Threshold band lower multiplier (0–1)
float  _K2SThreshMax;         // Threshold band upper multiplier (1–5)
float  _K2STightness;         // 0 = soft/wide → 1 = crisp/thin
float  _K2SPowerCurve;        // Post-pass power curve  (0.5–5)
float  _K2SSobelStrength;     // Edge opacity           (0–1)

// ── Shared K2 helpers ─────────────────────────────────────────────────────────
static const float2 K2S_DIRS[8] = {
    float2( 1.0000,  0.0000),
    float2( 0.7071,  0.7071),
    float2( 0.0000,  1.0000),
    float2(-0.7071,  0.7071),
    float2(-1.0000,  0.0000),
    float2(-0.7071, -0.7071),
    float2( 0.0000, -1.0000),
    float2( 0.7071, -0.7071),
};

void K2S_Sector(float2 uv2, float2 dir, float2 mrow0, float2 mrow1, float3 cc,
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

// ── Gaussian Sobel helper (9-tap or point) ────────────────────────────────────
float K2S_GaussLuma(float2 center, float blurR, float cW, float cardW, float diagW)
{
    float3 L = float3(0.299, 0.587, 0.114);
    float v = 0.0;
    v += dot(tex2D(u_BaseColorSampler, center).rgb,                                L) * cW;
    v += dot(tex2D(u_BaseColorSampler, center + float2( blurR,     0)).rgb,        L) * cardW;
    v += dot(tex2D(u_BaseColorSampler, center + float2(-blurR,     0)).rgb,        L) * cardW;
    v += dot(tex2D(u_BaseColorSampler, center + float2(     0,  blurR)).rgb,       L) * cardW;
    v += dot(tex2D(u_BaseColorSampler, center + float2(     0, -blurR)).rgb,       L) * cardW;
    v += dot(tex2D(u_BaseColorSampler, center + float2( blurR,  blurR)).rgb,       L) * diagW;
    v += dot(tex2D(u_BaseColorSampler, center + float2(-blurR,  blurR)).rgb,       L) * diagW;
    v += dot(tex2D(u_BaseColorSampler, center + float2( blurR, -blurR)).rgb,       L) * diagW;
    v += dot(tex2D(u_BaseColorSampler, center + float2(-blurR, -blurR)).rgb,       L) * diagW;
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
    float E   = gx * gx,  F = gx * gy,  G = gy * gy;

    float disc = sqrt(max(0.0, (E-G)*(E-G) + 4.0*F*F));
    float lam1 = (E+G+disc)*0.5,  lam2 = (E+G-disc)*0.5;
    float phi  = 0.5 * atan2(2.0*F, E - G + 1e-7) + 1.5707963;
    float A    = saturate((lam1 - lam2) / (lam1 + lam2 + 1e-7));

    float r     = _K2SKuwRadius * 0.001;
    float alpha = max(_K2SKuwAlpha, 0.1);
    float ea    = (alpha + A) / alpha * r;
    float eb    = alpha / (alpha + A) * r;
    float cp    = cos(phi),  sp = sin(phi);
    float2 mr0  = float2(ea*cp,  eb*sp);
    float2 mr1  = float2(-ea*sp, eb*cp);

    float3 cc = tex2D(u_BaseColorSampler, uv).rgb;

    float3 m0,m1,m2,m3,m4,m5,m6,m7;
    float  sv0,sv1,sv2,sv3,sv4,sv5,sv6,sv7;
    K2S_Sector(uv, K2S_DIRS[0], mr0, mr1, cc, m0, sv0);
    K2S_Sector(uv, K2S_DIRS[1], mr0, mr1, cc, m1, sv1);
    K2S_Sector(uv, K2S_DIRS[2], mr0, mr1, cc, m2, sv2);
    K2S_Sector(uv, K2S_DIRS[3], mr0, mr1, cc, m3, sv3);
    K2S_Sector(uv, K2S_DIRS[4], mr0, mr1, cc, m4, sv4);
    K2S_Sector(uv, K2S_DIRS[5], mr0, mr1, cc, m5, sv5);
    K2S_Sector(uv, K2S_DIRS[6], mr0, mr1, cc, m6, sv6);
    K2S_Sector(uv, K2S_DIRS[7], mr0, mr1, cc, m7, sv7);

    float tau = _K2SKuwTau,  q = _K2SKuwQ;
    float w0=1.0/pow(max(tau,sv0),q), w1=1.0/pow(max(tau,sv1),q);
    float w2=1.0/pow(max(tau,sv2),q), w3=1.0/pow(max(tau,sv3),q);
    float w4=1.0/pow(max(tau,sv4),q), w5=1.0/pow(max(tau,sv5),q);
    float w6=1.0/pow(max(tau,sv6),q), w7=1.0/pow(max(tau,sv7),q);
    float wsum = w0+w1+w2+w3+w4+w5+w6+w7;
    float3 kResult = (m0*w0+m1*w1+m2*w2+m3*w3+m4*w4+m5*w5+m6*w6+m7*w7) / max(wsum,1e-7);

    color.rgb = lerp(color.rgb, kResult, _K2SKuwStrength);

    // ════════════════════════════════════════════════════════════════════════
    // Phase 2 — Gaussian Sobel edge detection
    // ════════════════════════════════════════════════════════════════════════
    float off  = _K2SSobelSampleDist * 0.001;
    float blur = _K2SBlurRadius      * 0.001;

    float cW, cardW, diagW;
    if (_K2SEnableGaussBlur > 0.5)
    {
        float totalW = _K2SCenterWeight + 4.0*_K2SCardinalWeight + 4.0*_K2SDiagonalWeight;
        totalW = max(totalW, 0.0001);
        cW    = _K2SCenterWeight   / totalW;
        cardW = _K2SCardinalWeight / totalW;
        diagW = _K2SDiagonalWeight / totalW;
    }
    else { cW = 1.0; cardW = 0.0; diagW = 0.0; }

    float tl = K2S_GaussLuma(uv + float2(-off,  off), blur, cW, cardW, diagW);
    float t  = K2S_GaussLuma(uv + float2(   0,  off), blur, cW, cardW, diagW);
    float tr = K2S_GaussLuma(uv + float2( off,  off), blur, cW, cardW, diagW);
    float l  = K2S_GaussLuma(uv + float2(-off,    0), blur, cW, cardW, diagW);
    float ri = K2S_GaussLuma(uv + float2( off,    0), blur, cW, cardW, diagW);
    float bl = K2S_GaussLuma(uv + float2(-off, -off), blur, cW, cardW, diagW);
    float b  = K2S_GaussLuma(uv + float2(   0, -off), blur, cW, cardW, diagW);
    float br = K2S_GaussLuma(uv + float2( off, -off), blur, cW, cardW, diagW);

    float sobelX  = (tr + 2.0*ri + br) - (tl + 2.0*l  + bl);
    float sobelY  = (tl + 2.0*t  + tr) - (bl + 2.0*b  + br);
    float edgeMag = sqrt(sobelX*sobelX + sobelY*sobelY);

    float minEdge = _K2SThreshold * _K2SThreshMin;
    float maxEdge = _K2SThreshold * _K2SThreshMax;
    float edge    = smoothstep(minEdge, maxEdge, edgeMag);

    float hw1 = lerp(0.5, 0.03, _K2STightness);
    edge = smoothstep(0.5 - hw1, 0.5 + hw1, edge);
    float hw2 = lerp(0.5, 0.15, _K2STightness);
    edge = smoothstep(0.5 - hw2, 0.5 + hw2, edge);
    float hw3 = lerp(0.5, 0.25, _K2STightness);
    edge = smoothstep(0.5 - hw3, 0.5 + hw3, edge);
    float hw4 = lerp(0.5, 0.35, _K2STightness);
    edge = smoothstep(0.5 - hw4, 0.5 + hw4, edge);

    edge = pow(edge, _K2SPowerCurve);
    edge *= _K2SSobelStrength;

    color.rgb = lerp(color.rgb, _InnerLineColor.rgb, edge);
    return color;
}

#endif // NPR_EFFECT_KUWAHARA2_SOBEL_INCLUDED
