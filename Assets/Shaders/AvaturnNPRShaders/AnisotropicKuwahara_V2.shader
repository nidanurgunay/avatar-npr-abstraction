// =============================================================================
// Anisotropic Kuwahara Filter V2 — corrected implementation
// =============================================================================
// Based on Kyprianidis et al. "Image and Video Abstraction by Anisotropic
// Kuwahara Filtering" (Pacific Graphics 2009)
//
// Changes from V1 (AnisotropicKuwahara.shader):
//
//   1. Soft sector assignment (the main fix).
//      V1 used hard integer assignment: sectorIdx = int(angle / sectorAngle).
//      Samples near sector boundaries were misclassified, inflating all sector
//      variances equally → equal weights → weighted average = blur.
//      V2 uses cosine polynomial weighting: v_k = max(0, cos(θ−φ_k))^(2n).
//      Every sample contributes to all sectors simultaneously with angular
//      falloff, giving reliable variance estimates per sector.
//
//   2. Correct inverse-std-dev output weighting.
//      V1: w = 1/(1 + pow(variance * 1000.0, 0.5*q))  — ad hoc scale.
//      V2: w = 1/pow(max(tau, sqrt(variance)), q)       — Kyprianidis eq. 6.
//      Using sigma (std dev) instead of variance sharpens the winner-takes-all
//      ratio from ~10x to ~1000x.
//
//   3. Correct ellipse axes (Kyprianidis §3.3.1).
//      V1 at A=0: a = b = radius * 0.5.
//      V2 at A=0: a = b = radius.
//      V1 was sampling a kernel half the intended size.
//
//   4. Anisotropic Gaussian weight follows the ellipse axes.
//      V1: exp(-2 * dist²) — isotropic.
//      V2: exp(-0.5 * (px²/a² + py²/b²)) — ellipse-aligned.
//
// Parameters:
//   _KernelSize  — sampling radius in pixels (try 8–14 for visible brushstrokes)
//   _SectorCount — number of sectors, 4 or 8 (paper uses 8)
//   _Sharpness   — q: inverse-std-dev exponent; higher = sharper strokes (8 recommended)
//   _Hardness    — n: cosine sector weight exponent; higher = crisper sector edges (2–4)
//   _ZeroCrossing — unused, kept for C# feature compatibility
// =============================================================================

Shader "NPR/AnisotropicKuwahara_V2"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off Cull Off ZTest Always

        // =====================================================================
        // PASS 0: Structure Tensor
        // Sobel on luminance -> packs (gx2, gx.gy, gy2) into RGB
        // Unchanged from V1.
        // =====================================================================
        Pass
        {
            Name "StructureTensor"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragStructureTensor
            #pragma target 3.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float4 _BlitTexture_TexelSize;

            float Luminance3(float3 c)
            {
                return dot(c, float3(0.2126, 0.7152, 0.0722));
            }

            float4 FragStructureTensor(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;
                float2 d  = _BlitTexture_TexelSize.xy;
                float tl = Luminance3(SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, saturate(uv + float2(-d.x,  d.y)), 0).rgb);
                float  l = Luminance3(SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, saturate(uv + float2(-d.x,  0.0)), 0).rgb);
                float bl = Luminance3(SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, saturate(uv + float2(-d.x, -d.y)), 0).rgb);
                float  t = Luminance3(SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, saturate(uv + float2( 0.0,  d.y)), 0).rgb);
                float  b = Luminance3(SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, saturate(uv + float2( 0.0, -d.y)), 0).rgb);
                float tr = Luminance3(SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, saturate(uv + float2( d.x,  d.y)), 0).rgb);
                float  r = Luminance3(SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, saturate(uv + float2( d.x,  0.0)), 0).rgb);
                float br = Luminance3(SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, saturate(uv + float2( d.x, -d.y)), 0).rgb);

                float gx = -tl - 2.0*l - bl + tr + 2.0*r + br;
                float gy = -tl - 2.0*t - tr + bl + 2.0*b + br;

                return float4(gx*gx, gx*gy, gy*gy, 1.0);
            }
            ENDHLSL
        }

        // =====================================================================
        // PASS 1: Gaussian Blur on Structure Tensor (separable, 5-tap)
        // Unchanged from V1.
        // =====================================================================
        Pass
        {
            Name "TensorBlur"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragTensorBlur
            #pragma target 3.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float4 _BlitTexture_TexelSize;
            float4 _BlurDirection;

            float4 FragTensorBlur(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv     = input.texcoord;
                float2 offset = _BlurDirection.xy * _BlitTexture_TexelSize.xy;

                float4 result  = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, uv - 2.0*offset, 0) * 0.0625;
                       result += SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, uv -     offset, 0)  * 0.25;
                       result += SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, uv             , 0)  * 0.375;
                       result += SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, uv +     offset, 0)  * 0.25;
                       result += SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, uv + 2.0*offset, 0)  * 0.0625;
                return result;
            }
            ENDHLSL
        }

        // =====================================================================
        // PASS 2: Anisotropic Kuwahara Filter — V2 (corrected)
        // =====================================================================
        Pass
        {
            Name "KuwaharaFilter"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragKuwahara
            #pragma target 3.5

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float4 _BlitTexture_TexelSize;

            TEXTURE2D_X(_StructureTensor);
            SAMPLER(sampler_StructureTensor);

            #if defined(SHADER_API_MOBILE)
                #define MAX_RADIUS 8
            #else
                #define MAX_RADIUS 32
            #endif

            int   _KernelSize;
            int   _SectorCount;
            float _Sharpness;     // q in paper eq. 6: inverse-std-dev exponent
            float _Hardness;      // n: cosine sector weight exponent (higher = crisper sector edges)
            float _ZeroCrossing;  // unused; kept for C# feature compatibility

            float4 FragKuwahara(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;
                float2 d  = _BlitTexture_TexelSize.xy;

                // Read smoothed structure tensor
                float3 tensor = SAMPLE_TEXTURE2D_X_LOD(_StructureTensor, sampler_StructureTensor, uv, 0).rgb;
                float E = tensor.r, F = tensor.g, G = tensor.b;

                // Eigenvalue decomposition (paper eq. 1)
                float disc    = sqrt(max((E-G)*(E-G) + 4.0*F*F, 0.0));
                float lambda1 = 0.5*(E+G+disc);
                float lambda2 = 0.5*(E+G-disc);
                float angle   = 0.5 * atan2(2.0*F, E-G);
                float A       = (lambda1+lambda2 > 1e-8)
                                ? (lambda1-lambda2)/(lambda1+lambda2) : 0.0;

                // Ellipse axes: Kyprianidis 2009 §3.3.1, alpha=1
                // a = (1+A)*r, b = r/(1+A). At A=0: a=b=r. Area = r² (constant).
                int   radius = min(_KernelSize, MAX_RADIUS);
                float r      = float(radius);
                float a      = r * (1.0 + A);
                float b      = r / max(1.0 + A, 1e-4);
                a = max(a, 1.0);
                b = max(b, 1.0);

                float cosA = cos(angle);
                float sinA = sin(angle);

                int N = clamp(_SectorCount, 4, 8);
                float q   = max(_Sharpness, 0.5);
                float n   = max(_Hardness,  0.5);
                float tau = 0.01; // variance floor (Kyprianidis §3.3.1)

                float4 sectorMeanW    [8];  // weighted colour sum
                float  sectorWeight   [8];  // total sector weight
                float  sectorVarianceW[8];  // weighted |c|² sum for variance

                [unroll]
                for (int s = 0; s < 8; s++) {
                    sectorMeanW[s]     = 0;
                    sectorWeight[s]    = 0;
                    sectorVarianceW[s] = 0;
                }

                // Accumulate samples with soft sector assignment
                [loop]
                for (int j = -MAX_RADIUS; j <= MAX_RADIUS; j++)
                {
                    [loop]
                    for (int i = -MAX_RADIUS; i <= MAX_RADIUS; i++)
                    {
                        if (abs(i) > radius || abs(j) > radius) continue;

                        // Rotate pixel offset to feature-aligned ellipse space
                        float px = cosA*float(i) + sinA*float(j);
                        float py = -sinA*float(i) + cosA*float(j);

                        // Ellipse membership
                        float normSq = (px*px)/(a*a) + (py*py)/(b*b);
                        if (normSq > 1.0) continue;

                        // Anisotropic Gaussian: wide along feature, narrow across it
                        float w_gauss = exp(-0.5 * normSq * 4.0);

                        float sampleAngle = atan2(py, px);
                        float2 sampleUV = saturate(uv + float2(float(i), float(j)) * d);
                        float4 col = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, sampleUV, 0);

                        // Soft sector assignment (Bug 1 fix): each sample contributes to ALL
                        // sectors with cosine^(2n) angular weighting — Kyprianidis 2009.
                        [unroll]
                        for (int k = 0; k < 8; k++)
                        {
                            if (k >= N) break;

                            float phi_k = TWO_PI * float(k) / float(N);
                            float delta = sampleAngle - phi_k;
                            // Wrap delta to [-pi, pi]
                            delta = delta - floor(delta * INV_TWO_PI + 0.5) * TWO_PI;
                            float c_k = max(0.0, cos(delta));
                            // pow(c_k, 2n) — higher n → sharper sector edges
                            float v_k = (c_k > 0.0) ? pow(c_k, 2.0 * n) : 0.0;
                            float wv  = w_gauss * v_k;

                            sectorMeanW    [k] += col * wv;
                            sectorWeight   [k] += wv;
                            sectorVarianceW[k] += dot(col.rgb, col.rgb) * wv;
                        }
                    }
                }

                // Blend sectors weighted by inverse standard deviation (Bug 2+3 fix)
                // w_k = 1/sigma_k^q  (Kyprianidis eq. 6)
                float4 result = 0;
                float  totalW = 0;

                [unroll]
                for (int k2 = 0; k2 < 8; k2++)
                {
                    if (k2 >= N) break;
                    if (sectorWeight[k2] < 1e-6) continue;

                    float4 mean     = sectorMeanW[k2] / sectorWeight[k2];
                    float  meanSqL  = sectorVarianceW[k2] / sectorWeight[k2];
                    // trace of RGB covariance matrix = E[|c|²] - |E[c]|²
                    float  variance = max(meanSqL - dot(mean.rgb, mean.rgb), 0.0);
                    float  sigma    = sqrt(variance);  // std dev, not variance

                    float w_k = 1.0 / pow(max(tau, sigma), q);

                    result += mean * w_k;
                    totalW += w_k;
                }

                return (totalW > 1e-6)
                    ? result / totalW
                    : SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, uv, 0);
            }
            ENDHLSL
        }

        // =====================================================================
        // PASS 3: Masked Composite
        // Unchanged from V1.
        // =====================================================================
        Pass
        {
            Name "MaskedComposite"
            ZWrite Off Cull Off ZTest Always

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragMaskedComposite

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D_X(_KuwaharaResult);
            TEXTURE2D_X(_AvatarMask);

            float4 FragMaskedComposite(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv       = input.texcoord;
                float4 original = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture,    sampler_LinearClamp, uv, 0);
                float4 kuwahara = SAMPLE_TEXTURE2D_X_LOD(_KuwaharaResult, sampler_LinearClamp, uv, 0);
                float  mask     = SAMPLE_TEXTURE2D_X_LOD(_AvatarMask,     sampler_LinearClamp, uv, 0).r;
                return lerp(original, kuwahara, mask);
            }
            ENDHLSL
        }
    }
}
