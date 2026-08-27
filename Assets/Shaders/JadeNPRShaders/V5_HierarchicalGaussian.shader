// V5 — Hierarchical Edge Detection with Gaussian Pre-blur
// Three-layer hierarchical edge detection (depth proxy, normal discontinuity,
// color Roberts Cross) where the color layer is optionally pre-smoothed with
// a 9-tap Gaussian before the Roberts Cross operator.
//
// Technique breakdown:
//   Depth  layer — ddx/ddy of camera-distance proxy → smoothstep threshold
//   Normal layer — ddx/ddy of world-space normal     → smoothstep threshold
//   Color  layer — 4-tap Roberts Cross on texture luminance, each tap
//                  optionally pre-blurred by a 9-tap Gaussian kernel
//   Fusion       — weighted max-pooling of the three layers
//   Adaptive     — brightness-based suppression to protect highlights

Shader "Custom/V5_HierarchicalGaussian"
{
    Properties
    {
        [Header(Base)]
        _Color            ("Main Color",       Color)      = (1,1,1,1)
        _MainTex          ("Texture",          2D)         = "white" {}
        _TextureIntensity ("Texture Intensity",Range(0,1)) = 1.0

        [Header(XToon 2D Ramp Lighting)]
        _ToonRamp         ("2D Toon Ramp",      2D)         = "white" {}
        _LightSensitivity ("Light Sensitivity", Range(0,1)) = 0.8
        _RampSmoothing    ("Ramp Smoothing",    Range(0,0.5)) = 0.05
        _ShadowColor      ("Shadow Color",      Color)      = (0.3,0.3,0.45,1)
        _ShadowStrength   ("Shadow Strength",   Range(0,1)) = 0.5
        [KeywordEnum(Depth, Curvature, Manual)] _DetailMode ("Detail Mode", Float) = 0
        _DetailBias  ("Detail Bias", Range(0,1))   = 0.5
        _DepthNear   ("Depth Near",  Range(0,20))  = 5.0
        _DepthFar    ("Depth Far",   Range(1,100)) = 50.0
        _ManualDetail("Manual Detail", Range(0,1)) = 0.5
        _AmbientColor   ("Ambient Color",   Color)         = (0.3,0.3,0.3,1)
        [Toggle] _EnableRim ("Enable Rim Lighting", Float) = 1
        _RimColor       ("Rim Color",       Color)         = (0.408,0.408,0.408,1)
        _RimPower       ("Rim Power",       Range(0.5,10)) = 3.0

        [Header(Outer Outline)]
        _OuterOutlineWidth ("Outline Width", Range(0,0.05))  = 0.005
        _OuterOutlineColor ("Outline Color", Color)          = (0,0,0,1)

        [Header(Edge   Depth Layer)]
        [Toggle] _EnableDepthEdge ("Enable Depth Edge", Float) = 1
        _HDepthThreshold ("Depth Threshold", Range(0.001,0.5)) = 0.05
        _HDepthWeight    ("Depth Weight",    Range(0,1))        = 1.0
        _HDepthScale     ("Depth Scale",     Range(1,100))      = 10.0

        [Header(Edge   Normal Layer)]
        [Toggle] _EnableNormalEdge ("Enable Normal Edge", Float) = 1
        _HNormalThreshold ("Normal Threshold", Range(0.05,1.0)) = 0.3
        _HNormalWeight    ("Normal Weight",    Range(0,1))       = 1.0

        [Header(Edge   Color Layer)]
        [Toggle] _EnableColorEdge ("Enable Color Edge", Float) = 1
        _HColorThreshold ("Color Threshold",  Range(0.01,0.5)) = 0.1
        _HColorWeight    ("Color Weight",     Range(0,1))       = 0.5
        _HEdgeWidth      ("Sample Distance",  Range(0.5,10.0)) = 1.0

        [Header(Gaussian Preblur on Color Layer)]
        [Toggle] _EnableGaussBlur  ("Enable Gaussian Preblur", Float) = 1
        _HBlurRadius      ("Blur Radius (sigma)",Range(0.1,5.0)) = 0.5
        _HCenterWeight    ("Center Weight",   Range(0,1))         = 0.25
        _HCardinalWeight  ("Cardinal Weight", Range(0,0.5))       = 0.125
        _HDiagonalWeight  ("Diagonal Weight", Range(0,0.25))      = 0.0625
        _HXDoGK           ("XDoG Radius Ratio k",   Range(1.1,4.0)) = 1.6
        _HXDoGTau         ("XDoG Tau",              Range(0.9,1.0)) = 0.98
        _HXDoGPhi         ("XDoG Sharpness (Phi)",  Range(1,50))    = 10.0

        [Header(Edge Output)]
        _HEdgeColor       ("Edge Color",       Color)      = (0,0,0,1)
        _HEdgeStrength    ("Edge Strength",    Range(0,1)) = 1.0
        _HAdaptiveStrength("Adaptive Strength",Range(0,1)) = 0.5

        [Header(Alpha Test)]
        [Toggle] _EnableAlphaTest ("Alpha Test", Float) = 0
        _AlphaCutoff ("Alpha Cutoff", Range(0,1)) = 0.07
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        // ── Outer outline (inverted hull) ────────────────────────────────────
        Pass
        {
            Name "OuterOutline"
            Cull Front
            ZWrite On
            ZTest Less

            HLSLPROGRAM
            #pragma vertex   vert_ol
            #pragma fragment frag_ol
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attr_OL { float4 vertex : POSITION; float3 normal : NORMAL; float2 uv : TEXCOORD0; };
            struct Vary_OL { float4 pos    : SV_POSITION; float2 uv  : TEXCOORD0; };

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _Color, _AmbientColor, _RimColor, _HEdgeColor, _OuterOutlineColor;
                float  _TextureIntensity, _ShadowStrength, _RimPower, _EnableRim;
                float  _OuterOutlineWidth;
                float  _EnableAlphaTest, _AlphaCutoff;
                float  _EnableDepthEdge,  _HDepthThreshold,  _HDepthWeight, _HDepthScale;
                float  _EnableNormalEdge, _HNormalThreshold, _HNormalWeight;
                float  _EnableColorEdge,  _HColorThreshold,  _HColorWeight, _HEdgeWidth;
                float  _EnableGaussBlur,  _HBlurRadius;
                float  _HCenterWeight, _HCardinalWeight, _HDiagonalWeight;
                float  _HXDoGK, _HXDoGTau, _HXDoGPhi;
                float  _HEdgeStrength, _HAdaptiveStrength;
                float4 _ShadowColor;
                float  _LightSensitivity, _RampSmoothing, _DetailBias, _DepthNear, _DepthFar, _ManualDetail;
            CBUFFER_END

            Vary_OL vert_ol(Attr_OL v)
            {
                Vary_OL o;
                VertexPositionInputs pi = GetVertexPositionInputs(v.vertex.xyz);
                VertexNormalInputs   ni = GetVertexNormalInputs(v.normal);
                o.pos = TransformWorldToHClip(pi.positionWS + ni.normalWS * _OuterOutlineWidth);
                o.uv  = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            half4 frag_ol(Vary_OL i) : SV_Target
            {
                if (_EnableAlphaTest > 0.5)
                    clip(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).a - _AlphaCutoff);
                return _OuterOutlineColor;
            }
            ENDHLSL
        }

        // ── Forward lit ──────────────────────────────────────────────────────
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            Cull Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag
            #pragma target   3.0
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma shader_feature_local _DETAILMODE_DEPTH _DETAILMODE_CURVATURE _DETAILMODE_MANUAL

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attr
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv     : TEXCOORD0;
            };

            struct Vary
            {
                float4 pos   : SV_POSITION;
                float2 uv    : TEXCOORD0;
                float3 posWS : TEXCOORD1;
                float3 nWS   : TEXCOORD2;
            };

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            TEXTURE2D(_ToonRamp); SAMPLER(sampler_ToonRamp);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _Color, _AmbientColor, _RimColor, _HEdgeColor, _OuterOutlineColor;
                float  _TextureIntensity, _ShadowStrength, _RimPower, _EnableRim;
                float  _OuterOutlineWidth;
                float  _EnableAlphaTest, _AlphaCutoff;
                float  _EnableDepthEdge,  _HDepthThreshold,  _HDepthWeight, _HDepthScale;
                float  _EnableNormalEdge, _HNormalThreshold, _HNormalWeight;
                float  _EnableColorEdge,  _HColorThreshold,  _HColorWeight, _HEdgeWidth;
                float  _EnableGaussBlur,  _HBlurRadius;
                float  _HCenterWeight, _HCardinalWeight, _HDiagonalWeight;
                float  _HXDoGK, _HXDoGTau, _HXDoGPhi;
                float  _HEdgeStrength, _HAdaptiveStrength;
                float4 _ShadowColor;
                float  _LightSensitivity, _RampSmoothing, _DetailBias, _DepthNear, _DepthFar, _ManualDetail;
            CBUFFER_END

            static const float3 LUMA = float3(0.299, 0.587, 0.114);

            // 9-tap Gaussian-weighted luminance sample centred at uv.
            // When blur radius is 0 this degenerates to a point sample at the centre.
            float GaussianLuma(float2 uv, float br, float cW, float cardW, float diagW)
            {
                float s = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv).rgb,                LUMA) * cW;
                s += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2( br,  0)).rgb, LUMA) * cardW;
                s += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-br,  0)).rgb, LUMA) * cardW;
                s += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(  0, br)).rgb, LUMA) * cardW;
                s += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(  0,-br)).rgb, LUMA) * cardW;
                s += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2( br, br)).rgb, LUMA) * diagW;
                s += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-br, br)).rgb, LUMA) * diagW;
                s += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2( br,-br)).rgb, LUMA) * diagW;
                s += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-br,-br)).rgb, LUMA) * diagW;
                return s;
            }

            Vary vert(Attr v)
            {
                Vary o;
                VertexPositionInputs pi = GetVertexPositionInputs(v.vertex.xyz);
                VertexNormalInputs   ni = GetVertexNormalInputs(v.normal);
                o.pos   = pi.positionCS;
                o.uv    = TRANSFORM_TEX(v.uv, _MainTex);
                o.posWS = pi.positionWS;
                o.nWS   = ni.normalWS;
                return o;
            }

            half4 frag(Vary IN) : SV_Target
            {
                half4 texColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);
                if (_EnableAlphaTest > 0.5) clip(texColor.a - _AlphaCutoff);

                half3 baseColor = lerp(_Color.rgb, texColor.rgb * _Color.rgb, _TextureIntensity);
                half4 albedo    = half4(baseColor, texColor.a * _Color.a);

                float3 nWS = normalize(IN.nWS);

                // XToon 2D Ramp Shading
                Light mainLight = GetMainLight();
                float3 lightDir = normalize(mainLight.direction);
                float NdotL = dot(nWS, lightDir);
                float rampU = lerp(0.5, saturate(NdotL * 0.5 + 0.5), _LightSensitivity);
                float rampV;
                #if defined(_DETAILMODE_CURVATURE)
                    float3 _dNx = ddx(nWS); float3 _dNy = ddy(nWS);
                    float _curv = length(_dNx) + length(_dNy);
                    rampV = saturate((1.0 - saturate(_curv * 10.0)) * (1.0 - _DetailBias) + _DetailBias);
                #elif defined(_DETAILMODE_MANUAL)
                    rampV = saturate(_ManualDetail);
                #else
                    float _xtDepth = length(_WorldSpaceCameraPos - IN.posWS);
                    rampV = saturate(saturate((_xtDepth - _DepthNear) / max(0.001, _DepthFar - _DepthNear)) + _DetailBias);
                #endif
                float3 rampColor = SAMPLE_TEXTURE2D(_ToonRamp, sampler_ToonRamp, float2(rampU, rampV)).rgb;
                float _aU = lerp(rampU, 0.5, rampV * 0.6);
                float _dS = lerp(_RampSmoothing, _RampSmoothing + 0.35, rampV);
                float shadowMask = smoothstep(0.5 - _dS, 0.5 + _dS, _aU);
                float3 toonBase = albedo.rgb * rampColor;
                float3 shadowedBase = lerp(toonBase * _ShadowColor.rgb, toonBase, shadowMask);
                float3 shaded = lerp(albedo.rgb, shadowedBase, _ShadowStrength);
                shaded += _AmbientColor.rgb * albedo.rgb;
                if (_EnableRim > 0.5)
                {
                    float3 vWS = normalize(_WorldSpaceCameraPos - IN.posWS);
                    float rim = pow(1.0 - saturate(dot(vWS, nWS)), _RimPower);
                    shaded += rim * _RimColor.rgb;
                }

                // ── Layer 1: Depth proxy (perspective-normalised distance gradient) ──
                // Dividing by distance makes the threshold clip-plane-relative:
                // the same threshold fires at similar angular depth jumps regardless
                // of whether the avatar is near or far from the camera.
                float depthLine = 0.0;
                if (_EnableDepthEdge > 0.5)
                {
                    float d    = length(IN.posWS - _WorldSpaceCameraPos);
                    float dDx  = abs(ddx(d));
                    float dDy  = abs(ddy(d));
                    float edge = sqrt(dDx * dDx + dDy * dDy) / max(d, 0.01) * _HDepthScale;
                    depthLine  = smoothstep(_HDepthThreshold - 0.001,
                                            _HDepthThreshold + 0.001, edge);
                }

                // ── Layer 2: Normal discontinuity (world-space) ──────────────
                float normalLine = 0.0;
                if (_EnableNormalEdge > 0.5)
                {
                    float3 dNdx = ddx(nWS);
                    float3 dNdy = ddy(nWS);
                    float  edge = sqrt(dot(dNdx, dNdx) + dot(dNdy, dNdy));
                    normalLine  = smoothstep(_HNormalThreshold - 0.02,
                                             _HNormalThreshold + 0.02, edge);
                }

                // ── Layer 3: XDoG texture edge (Difference of Gaussians) ──────
                // Replaces Roberts Cross. Compares fine (sigma) vs coarse (k*sigma)
                // Gaussian at the center pixel. Fires only where the fine blur sees
                // detail the coarse blur misses — suppresses gradual gradients that
                // caused the triple-edge artifact on thin features.
                float colorLine = 0.0;
                if (_EnableColorEdge > 0.5)
                {
                    float totalW = _HCenterWeight + 4.0*_HCardinalWeight + 4.0*_HDiagonalWeight;
                    totalW = max(totalW, 0.0001);
                    float cW    = _HCenterWeight   / totalW;
                    float cardW = _HCardinalWeight / totalW;
                    float diagW = _HDiagonalWeight / totalW;

                    float sigma1 = _HBlurRadius * 0.001;
                    float sigma2 = _HBlurRadius * _HXDoGK * 0.001;
                    float g1 = GaussianLuma(IN.uv, sigma1, cW, cardW, diagW);
                    float g2 = GaussianLuma(IN.uv, sigma2, cW, cardW, diagW);
                    float D  = g1 - _HXDoGTau * g2;
                    // _HColorThreshold gates D: only fires when D is more negative
                    // than -threshold (i.e. the edge is strong enough). Increasing
                    // threshold suppresses weaker gradients, exactly like the old slider.
                    colorLine = D < -_HColorThreshold
                        ? saturate(-tanh(_HXDoGPhi * (D + _HColorThreshold)))
                        : 0.0;
                }

                // ── Weighted max-pooling + AHEAD adaptive gain (normal layer only) ────
                // Inverse-linear AGC: amplifies edges in dark areas, leaves bright areas
                // and silhouette/texture layers unchanged (AHEAD §2.4 and §2.5).
                float L        = dot(albedo.rgb, LUMA);
                float adaptive = min(1.0 / (3.0 * L + 0.1), 4.0);
                adaptive = lerp(1.0, adaptive, _HAdaptiveStrength);

                float edgeFinal = max(depthLine * _HDepthWeight,
                                  max(normalLine * _HNormalWeight * adaptive,
                                      colorLine  * _HColorWeight));
                edgeFinal = smoothstep(0.2, 0.55, edgeFinal);
                edgeFinal = saturate(edgeFinal * _HEdgeStrength);

                shaded = lerp(shaded, _HEdgeColor.rgb, edgeFinal);
                return half4(shaded, albedo.a);
            }
            ENDHLSL
        }
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    CustomEditor "AvaturnPresetShaderGUI"
}
