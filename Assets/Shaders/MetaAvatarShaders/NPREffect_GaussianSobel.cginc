#ifndef NPR_EFFECT_GAUSSIAN_SOBEL_INCLUDED
#define NPR_EFFECT_GAUSSIAN_SOBEL_INCLUDED

// Gaussian pre-filtered Sobel edge detection — V4 strategy.
// Configurable Gaussian weights (normalised), configurable threshold band,
// 4 progressive smoothstep passes controlled by a single Tightness value,
// and an optional power curve.
// Requires ENABLE_NPR_EDGES + EFFECT_GAUSS_SOBEL keywords.

float4 _GSobelEdgeColor;         // Edge colour (default black)
float  _GSobelEnableGaussBlur;   // 1 = 9-tap Gaussian pre-blur, 0 = plain point sample
float  _GSobelSampleDist;        // Sobel kernel UV offset (0–10, × 0.001)
float  _GSobelBlurRadius;     // Per-sample Gaussian blur radius (0–5, × 0.001)
float  _GSobelCenterWeight;   // Gaussian center tap weight (0.1–0.5)
float  _GSobelCardinalWeight; // Gaussian cardinal tap weight (0–0.3)
float  _GSobelDiagonalWeight; // Gaussian diagonal tap weight (0–0.1)
float  _GSobelThreshold;      // Base edge threshold (0–0.5)
float  _GSobelThreshMin;      // Threshold band lower multiplier (0–1)
float  _GSobelThreshMax;      // Threshold band upper multiplier (1–5)
float  _GSobelTightness;      // 0=wide/soft, 1=tight/crisp — drives all 4 smoothstep passes
float  _GSobelPowerCurve;     // Post-sharpening power curve (0.5–5)
float  _GSobelStrength;       // Overall edge opacity (0–1)

// 9-tap Gaussian weighted luminance centred on `center`
float GaussianLuma(float2 center, float blurR, float cW, float cardW, float diagW)
{
    float3 L = float3(0.2126, 0.7152, 0.0722);
    float  v = 0.0;
    v += dot(tex2D(u_BaseColorSampler, center).rgb,                                L) * cW;
    v += dot(tex2D(u_BaseColorSampler, center + float2( blurR,     0)).rgb,        L) * cardW;
    v += dot(tex2D(u_BaseColorSampler, center + float2(-blurR,     0)).rgb,        L) * cardW;
    v += dot(tex2D(u_BaseColorSampler, center + float2(    0,  blurR)).rgb,        L) * cardW;
    v += dot(tex2D(u_BaseColorSampler, center + float2(    0, -blurR)).rgb,        L) * cardW;
    v += dot(tex2D(u_BaseColorSampler, center + float2( blurR,  blurR)).rgb,       L) * diagW;
    v += dot(tex2D(u_BaseColorSampler, center + float2(-blurR,  blurR)).rgb,       L) * diagW;
    v += dot(tex2D(u_BaseColorSampler, center + float2( blurR, -blurR)).rgb,       L) * diagW;
    v += dot(tex2D(u_BaseColorSampler, center + float2(-blurR, -blurR)).rgb,       L) * diagW;
    return v;
}

float4 ApplyNPREffect(float4 color, float2 uv, half3 worldNormal, half3 worldViewDir)
{
    float off  = _GSobelSampleDist * 0.001;
    float blur = _GSobelBlurRadius * 0.001;

    // When Gaussian blur is disabled each Sobel position collapses to a point sample
    float cW, cardW, diagW;
    if (_GSobelEnableGaussBlur > 0.5)
    {
        float totalW = _GSobelCenterWeight + 4.0 * _GSobelCardinalWeight + 4.0 * _GSobelDiagonalWeight;
        totalW = max(totalW, 0.0001);
        cW    = _GSobelCenterWeight   / totalW;
        cardW = _GSobelCardinalWeight / totalW;
        diagW = _GSobelDiagonalWeight / totalW;
    }
    else { cW = 1.0; cardW = 0.0; diagW = 0.0; }

    float tl = GaussianLuma(uv + float2(-off,  off), blur, cW, cardW, diagW);
    float t  = GaussianLuma(uv + float2(   0,  off), blur, cW, cardW, diagW);
    float tr = GaussianLuma(uv + float2( off,  off), blur, cW, cardW, diagW);
    float l  = GaussianLuma(uv + float2(-off,    0), blur, cW, cardW, diagW);
    float r  = GaussianLuma(uv + float2( off,    0), blur, cW, cardW, diagW);
    float bl = GaussianLuma(uv + float2(-off, -off), blur, cW, cardW, diagW);
    float b  = GaussianLuma(uv + float2(   0, -off), blur, cW, cardW, diagW);
    float br = GaussianLuma(uv + float2( off, -off), blur, cW, cardW, diagW);

    float sobelX  = (tr + 2*r + br) - (tl + 2*l + bl);
    float sobelY  = (tl + 2*t + tr) - (bl + 2*b + br);
    float edgeMag = sqrt(sobelX*sobelX + sobelY*sobelY);

    // Configurable threshold band (lower × min, upper × max)
    float minEdge = _GSobelThreshold * _GSobelThreshMin;
    float maxEdge = _GSobelThreshold * _GSobelThreshMax;
    float edge    = smoothstep(minEdge, maxEdge, edgeMag);

    // 4 progressive smoothstep passes — Tightness drives all half-widths simultaneously
    // At Tightness=0: each hw=0.5 → pass is a no-op (linear through)
    // At Tightness=1: hw shrinks toward 0.03/0.15/0.25/0.35 → crisp snapping
    float hw1 = lerp(0.5, 0.03, _GSobelTightness);
    edge = smoothstep(0.5 - hw1, 0.5 + hw1, edge);
    float hw2 = lerp(0.5, 0.15, _GSobelTightness);
    edge = smoothstep(0.5 - hw2, 0.5 + hw2, edge);
    float hw3 = lerp(0.5, 0.25, _GSobelTightness);
    edge = smoothstep(0.5 - hw3, 0.5 + hw3, edge);
    float hw4 = lerp(0.5, 0.35, _GSobelTightness);
    edge = smoothstep(0.5 - hw4, 0.5 + hw4, edge);

    // Power curve: >1 suppresses soft halos, <1 boosts thin edges
    edge = pow(edge, _GSobelPowerCurve);

    edge *= _GSobelStrength;

    color.rgb = lerp(color.rgb, _GSobelEdgeColor.rgb, edge);
    return color;
}

#endif // NPR_EFFECT_GAUSSIAN_SOBEL_INCLUDED
