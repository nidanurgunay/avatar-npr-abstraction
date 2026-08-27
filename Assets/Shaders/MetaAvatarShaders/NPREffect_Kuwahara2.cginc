#ifndef NPR_EFFECT_KUWAHARA2_INCLUDED
#define NPR_EFFECT_KUWAHARA2_INCLUDED

// Single-scale anisotropic Kuwahara filter (Kyprianidis, NPAR 2011 §3.3).
// Key differences from the isotropic Technique 6:
//   • Structure tensor (from hardware ddx/ddy on the shaded luminance) estimates
//     dominant local orientation φ and anisotropy A.
//   • Filter region is an ellipse whose axes depend on A and whose rotation equals φ,
//     so brushstrokes follow surface features rather than screen axes.
//   • 8 overlapping sectors replace the 4 axis-aligned quadrants.
//   • Output is a soft inverse-variance weighted blend of sector means
//     (ω_i = max(τ, σ_i)^{-q}, Kyprianidis §3.3.1), not a hard min-variance pick.
// The multi-scale pyramid from the 2011 paper requires multiple render passes and
// cannot be implemented inside AppSpecificPostManipulation.
// Requires ENABLE_NPR_EDGES + EFFECT_KUWAHARA2 keywords.

float _K2Radius;    // Ellipse radius, UV-space  (0.5–8,    ×0.001)
float _K2Strength;  // Blend with original colour (0–1)
float _K2Alpha;     // Eccentricity tuning α      (0.5–3,   default 1.0)
float _K2Q;         // Sector-weight sharpness q  (1–16,    default 8.0)
float _K2Tau;       // Variance floor τ_w         (0.001–0.1, default 0.02)

// Pre-computed 8 unit-disc sector centre directions (avoids 8 cos/sin calls at runtime).
static const float2 K2_DIRS[8] = {
    float2( 1.0000,  0.0000),
    float2( 0.7071,  0.7071),
    float2( 0.0000,  1.0000),
    float2(-0.7071,  0.7071),
    float2(-1.0000,  0.0000),
    float2(-0.7071, -0.7071),
    float2( 0.0000, -1.0000),
    float2( 0.7071, -0.7071),
};

// One sector: 3 samples along the disc direction dir (at radii 0.45, 0.75, 1.0),
// plus the shared centre sample cc.  Returns Gaussian-weighted mean and std dev.
// mrow0/mrow1 are the rows of the transform R_{-φ}·diag(a,b) that maps a unit-disc
// point to a UV offset: uv_off = (dot(mrow0,q), dot(mrow1,q)).
void K2_Sector(float2 uv2, float2 dir, float2 mrow0, float2 mrow1, float3 cc,
               out float3 mean, out float sig)
{
    float3 s1 = tex2D(u_BaseColorSampler, uv2 + float2(dot(mrow0, dir*0.45), dot(mrow1, dir*0.45))).rgb;
    float3 s2 = tex2D(u_BaseColorSampler, uv2 + float2(dot(mrow0, dir*0.75), dot(mrow1, dir*0.75))).rgb;
    float3 s3 = tex2D(u_BaseColorSampler, uv2 + float2(dot(mrow0, dir      ), dot(mrow1, dir      ))).rgb;
    // Gaussian-inspired weights (centre 0.40, near 0.28, mid 0.20, far 0.12; sum = 1.0)
    mean = cc*0.40 + s1*0.28 + s2*0.20 + s3*0.12;
    float v = dot(cc-mean, cc-mean)*0.40 + dot(s1-mean, s1-mean)*0.28
            + dot(s2-mean, s2-mean)*0.20 + dot(s3-mean, s3-mean)*0.12;
    sig = sqrt(max(v, 0.0));
}

float4 ApplyNPREffect(float4 color, float2 uv, half3 worldNormal, half3 worldViewDir)
{
    // ── Structure tensor from shaded-colour luminance derivatives ─────────────
    // ddx/ddy give the per-pixel gradient of the final lit colour in screen space.
    // On smooth avatar surfaces this reliably reflects local feature orientation.
    float lum = dot(color.rgb, float3(0.2126, 0.7152, 0.0722)); // BT.709 luma weights
    float gx  = ddx(lum);
    float gy  = ddy(lum);
    float E   = gx * gx;
    float F   = gx * gy;
    float G   = gy * gy;

    // ── Eigenanalysis → dominant orientation φ, anisotropy A ─────────────────
    float disc = sqrt(max(0.0, (E - G)*(E - G) + 4.0*F*F));
    float lam1 = (E + G + disc) * 0.5;
    float lam2 = (E + G - disc) * 0.5;
    // φ: direction of minimum change (along the feature), paper eq. §3.2.2
    float phi  = 0.5 * atan2(2.0 * F, E - G + 1e-7) + 1.5707963; // + π/2
    float A    = saturate((lam1 - lam2) / (lam1 + lam2 + 1e-7));

    // ── Ellipse axes: a=(α+A)/α·r, b=α/(α+A)·r  (paper §3.3.1) ─────────────
    float r     = _K2Radius * 0.001;
    float alpha = max(_K2Alpha, 0.1);
    float ea    = (alpha + A) / alpha * r;   // major axis (along feature)
    float eb    = alpha / (alpha + A) * r;   // minor axis (across feature)

    // Transform matrix rows for  UV_off = R_{-φ}·diag(a,b)·q
    // R_{-φ} = [[cos φ, sin φ],[-sin φ, cos φ]]
    float cp     = cos(phi);
    float sp     = sin(phi);
    float2 mr0   = float2(ea * cp,  eb * sp);
    float2 mr1   = float2(-ea * sp, eb * cp);

    // Centre sample (shared across all 8 sectors)
    float3 cc = tex2D(u_BaseColorSampler, uv).rgb;

    // ── 8-sector inverse-variance weighted blend ──────────────────────────────
    float3 m0,m1,m2,m3,m4,m5,m6,m7;
    float  s0,s1,s2,s3,s4,s5,s6,s7;

    K2_Sector(uv, K2_DIRS[0], mr0, mr1, cc, m0, s0);
    K2_Sector(uv, K2_DIRS[1], mr0, mr1, cc, m1, s1);
    K2_Sector(uv, K2_DIRS[2], mr0, mr1, cc, m2, s2);
    K2_Sector(uv, K2_DIRS[3], mr0, mr1, cc, m3, s3);
    K2_Sector(uv, K2_DIRS[4], mr0, mr1, cc, m4, s4);
    K2_Sector(uv, K2_DIRS[5], mr0, mr1, cc, m5, s5);
    K2_Sector(uv, K2_DIRS[6], mr0, mr1, cc, m6, s6);
    K2_Sector(uv, K2_DIRS[7], mr0, mr1, cc, m7, s7);

    // ω_i = max(τ, σ_i)^{-q}  (paper §3.3.1, thresholding avoids flat-region artefacts)
    float tau = _K2Tau;
    float q   = _K2Q;
    float w0 = 1.0/pow(max(tau,s0),q),  w1 = 1.0/pow(max(tau,s1),q);
    float w2 = 1.0/pow(max(tau,s2),q),  w3 = 1.0/pow(max(tau,s3),q);
    float w4 = 1.0/pow(max(tau,s4),q),  w5 = 1.0/pow(max(tau,s5),q);
    float w6 = 1.0/pow(max(tau,s6),q),  w7 = 1.0/pow(max(tau,s7),q);

    float  wsum   = w0+w1+w2+w3+w4+w5+w6+w7;
    float3 result = (m0*w0 + m1*w1 + m2*w2 + m3*w3
                  +  m4*w4 + m5*w5 + m6*w6 + m7*w7) / max(wsum, 1e-7);

    color.rgb = lerp(color.rgb, result, _K2Strength);
    return color;
}

#endif // NPR_EFFECT_KUWAHARA2_INCLUDED
