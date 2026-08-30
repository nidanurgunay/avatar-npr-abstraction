// V6_ChromaticEdge — Head-specific shader
// Inverted Hull outline + XToon 2D Ramp + Gaussian Sobel (luminance) + Chromatic Edge Detection
// Chromatic edges: Sobel applied to a colour-proximity mask instead of luminance,
//   so edges fire specifically at lip/brow colour boundaries rather than all texture contrast.

Shader "Custom/ChromaticEdge"
{
    Properties
    {
        [Header(DEBUG AND VISUALIZATION)]
        [Toggle] _UseDebugDefaults ("Use Debug Defaults", Float) = 0
        [KeywordEnum(Final, RawSobel, AfterThreshold, AfterBlur, NormalEdge, LipMask, LipEdge, BrowMask, BrowEdge, BrowSuppress, SkinMask)] _DebugView ("Debug View", Float) = 0
        [Space(10)]

        [Header(Base)]
        _Color ("Main Color", Color) = (1,1,1,1)
        _MainTex ("Texture", 2D) = "white" {}
        _TextureIntensity ("Texture Intensity", Range(0, 1)) = 1.0

        [Header(Normal Map)]
        [Normal]
        _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Intensity", Range(0,2)) = 1.0

        [Header(XToon 2D Ramp Shading)]
        _ToonRamp ("2D Toon Ramp", 2D) = "white" {}
        _LightSensitivity ("Light Sensitivity", Range(0,1)) = 0.8
        _RampSmoothing ("Ramp Smoothing", Range(0,0.5)) = 0.05
        _ShadowColor ("Shadow Color", Color) = (0.3,0.3,0.45,1)
        _ShadowStrength ("Shadow Strength", Range(0,1)) = 0.7
        [KeywordEnum(Depth, Curvature, Manual)] _DetailMode ("Detail Mode", Float) = 0
        _DetailBias ("Detail Bias", Range(0,1)) = 0.5
        _DepthNear ("Depth Near", Range(0,20)) = 5.0
        _DepthFar ("Depth Far", Range(1,100)) = 50.0
        _ManualDetail ("Manual Detail", Range(0,1)) = 0.5

        [Header(Outer Outline)]
        [Toggle] _EnableOuterOutline ("Enable Outer Outline", Float) = 1
        _OuterOutlineWidth ("Outer Outline Width", Range(0, 0.5)) = 0.005
        _OuterOutlineColor ("Outer Outline Color", Color) = (0,0,0,1)
        [Toggle] _UseOutlineDepthOffset ("Use Depth Offset", Float) = 0
        _OutlineDepthBias ("Outline Depth Bias", Range(0, 5)) = 1.0

        [Header(Luminance Sobel  Standard)]
        [Toggle] _EnableTextureSobel ("Enable Texture Sobel", Float) = 1
        _InnerLineColor ("Inner Line Color", Color) = (0,0,0,1)
        _InnerLineThreshold ("Line Threshold", Range(0.001, 0.5)) = 0.2
        _InnerLineBlur ("Sample Distance", Range(0.0, 10.0)) = 0.5
        _InnerLineStrength ("Line Strength", Range(0, 1)) = 1.0

        [Header(Gaussian PreBlur  Shared)]
        [Toggle] _EnableGaussianBlur ("Enable Gaussian PreBlur", Float) = 1
        _BlurRadiusMultiplier ("Blur Radius Multiplier", Range(0.1, 10.0)) = 0.8
        _GaussianCenterWeight ("Center Weight", Range(0.0, 1.0)) = 0.25
        _GaussianCardinalWeight ("Cardinal Weight", Range(0.0, 0.5)) = 0.125
        _GaussianDiagonalWeight ("Diagonal Weight", Range(0.0, 0.25)) = 0.0625

        [Header(Filtering Presets)]
        [Toggle] _UseLightFiltering ("Light Filtering (V3 style)", Float) = 0
        [Toggle] _UseModerateFiltering ("Moderate Filtering (V4 style)", Float) = 0
        [Toggle] _UseAggressiveFiltering ("Aggressive Filtering (V5 style)", Float) = 0

        [Header(Edge Threshold and Shaping)]
        [Toggle] _EnableThreshold ("Enable Threshold", Float) = 1
        _ThresholdMinMultiplier ("Threshold Min Multiplier", Range(0.0, 1.0)) = 0.2
        _ThresholdMaxMultiplier ("Threshold Max Multiplier", Range(1.0, 5.0)) = 2.0
        [Toggle] _EnablePass1 ("Enable Pass 1 (Tightest)", Float) = 1
        [Toggle] _EnablePass2 ("Enable Pass 2", Float) = 1
        [Toggle] _EnablePass3 ("Enable Pass 3", Float) = 1
        [Toggle] _EnablePass4 ("Enable Pass 4 (Widest)", Float) = 1
        _SmoothstepTightness ("Smoothstep Tightness", Range(0.0, 1.0)) = 0.2
        [Toggle] _EnablePowerCurve ("Enable Power Curve", Float) = 1
        _PowerCurve ("Power Curve", Range(0.5, 5.0)) = 1.5

        [Header(Normal Edge Detection)]
        [Toggle] _EnableNormalEdges ("Enable Normal Edges", Float) = 0
        _NormalEdgeThreshold ("Normal Edge Threshold", Range(0.0, 1.0)) = 0.5
        _NormalEdgeStrength ("Normal Edge Strength", Range(0, 1)) = 0.5
        _NormalEdgeSmoothness ("Normal Edge Smoothness", Range(0.01, 0.5)) = 0.1

        [Header(Edge Combination  Standard)]
        _EdgeColor ("Standard Edge Color", Color) = (0,0,0,1)
        [KeywordEnum(Max, Add, Multiply)] _EdgeBlendMode ("Edge Blend Mode", Float) = 0

        // ──────────────────────────────────────────────────────
        [Header(Chromatic Edge Detection  Lip Line)]
        [Toggle] _EnableLipEdge ("Enable Lip Edge", Float) = 0
        _LipTargetColor ("Lip Target Color (pick from texture)", Color) = (0.65, 0.35, 0.30, 1)
        _LipColorTolerance ("Lip Color Tolerance", Range(0.01, 1.0)) = 0.15
        _LipEdgeSampleDist ("Lip Sample Distance", Range(0.0, 10.0)) = 1.0
        _LipEdgeThreshold ("Lip Edge Threshold", Range(0.001, 0.5)) = 0.15
        _LipEdgeSmoothWidth ("Lip Edge Smooth Width", Range(0.0, 1.0)) = 0.3
        _LipEdgePower ("Lip Edge Power Curve", Range(0.5, 5.0)) = 1.5
        _LipEdgeStrength ("Lip Edge Strength", Range(0, 1)) = 1.0
        _LipEdgeColor ("Lip Edge Color", Color) = (0.08, 0.02, 0.02, 1)
        [Space(5)]
        [Toggle] _EnableSkinBoundary ("Enable Skin Boundary Mode", Float) = 0
        _SkinTargetColor ("Skin Reference Color (pick from cheek/forehead)", Color) = (0.85, 0.65, 0.55, 1)
        _SkinColorTolerance ("Skin Color Tolerance", Range(0.01, 1.0)) = 0.2

        [Header(Chromatic Edge Detection  Eyebrows)]
        [Toggle] _EnableBrowEdge ("Enable Eyebrow Edge", Float) = 0
        _BrowTargetColor ("Brow Target Color (pick from texture)", Color) = (0.12, 0.08, 0.06, 1)
        _BrowColorTolerance ("Brow Color Tolerance", Range(0.01, 1.0)) = 0.12
        _BrowEdgeSampleDist ("Brow Sample Distance", Range(0.0, 10.0)) = 1.0
        _BrowEdgeThreshold ("Brow Edge Threshold", Range(0.001, 0.5)) = 0.15
        _BrowEdgeSmoothWidth ("Brow Edge Smooth Width", Range(0.0, 1.0)) = 0.3
        _BrowEdgePower ("Brow Edge Power Curve", Range(0.5, 5.0)) = 1.5
        _BrowEdgeStrength ("Brow Edge Strength", Range(0, 1)) = 1.0
        _BrowEdgeColor ("Brow Edge Color", Color) = (0.04, 0.03, 0.02, 1)
        [Space(5)]
        [Toggle] _BrowSuppressMouth ("Suppress Brow Near Mouth", Float) = 0
        _BrowMouthSuppressRadius ("Mouth Proximity Radius", Range(0.0, 15.0)) = 5.0
        _BrowMouthSuppressStrength ("Suppress Strength", Range(0, 1)) = 1.0
        // ──────────────────────────────────────────────────────

        [Header(Wide Lip Sobel  Far Corners)]
        [Toggle] _EnableWideLipSobel ("Enable Wide Corner Sobel", Float) = 0
        _LipFarOffsetScale ("Far Corner Scale (x near offset)", Range(1.5, 4.0)) = 2.0
        _LipWideCornerWeight ("Far Corner Weight", Range(0.0, 2.0)) = 0.5

        [Header(Rim and Ambient)]
        [Toggle] _EnableRim ("Enable Rim Lighting", Float) = 1
        _RimColor ("Rim Color", Color) = (0.408,0.408,0.408,1)
        _RimPower ("Rim Power", Range(0.1, 8.0)) = 3.0
        _AmbientColor ("Ambient Color", Color) = (0.3,0.3,0.3,1)

        [Header(Alpha Test)]
        [Toggle] _EnableAlphaTest ("Enable Alpha Test", Float) = 0
        _AlphaCutoff ("Alpha Cutoff", Range(0, 1)) = 0.07
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        // ─── PASS 1: INVERTED HULL OUTLINE ───────────────────────────────────
        Pass
        {
            Name "OuterOutline"
            Cull Front
            ZWrite On
            ZTest Less

            HLSLPROGRAM
            #pragma vertex vert_outline
            #pragma fragment frag_outline
            #pragma target 3.5
            #pragma shader_feature_local _USEOUTLINEDEPTHOFFSET_ON
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "OvrVertexFetchBridge.hlsl"

            struct appdata_outline
            {
                float4 vertex   : POSITION;
                float3 normal   : NORMAL;
                float2 uv       : TEXCOORD0;
                uint   vertexID : SV_VertexID;
            };
            struct v2f_outline
            {
                float4 pos : SV_POSITION;
                float2 uv  : TEXCOORD0;
            };

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            float4 _MainTex_ST;
            float  _OuterOutlineWidth;
            float4 _OuterOutlineColor;
            float  _EnableAlphaTest;
            float  _AlphaCutoff;
            float  _OutlineDepthBias;

            v2f_outline vert_outline(appdata_outline v)
            {
                v2f_outline o;
                OVR_FETCH_POS_NORM(v.vertex.xyz, v.normal, v.vertexID);
                VertexPositionInputs posInputs  = GetVertexPositionInputs(v.vertex.xyz);
                VertexNormalInputs   normInputs = GetVertexNormalInputs(v.normal);
                o.pos = TransformWorldToHClip(posInputs.positionWS + normInputs.normalWS * _OuterOutlineWidth);
                #if _USEOUTLINEDEPTHOFFSET_ON
                    o.pos.z -= _OutlineDepthBias * 0.0001;
                #endif
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            half4 frag_outline(v2f_outline i) : SV_Target
            {
                if (_EnableAlphaTest > 0.5)
                {
                    half alpha = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).a;
                    clip(alpha - _AlphaCutoff);
                }
                return _OuterOutlineColor;
            }
            ENDHLSL
        }

        // ─── PASS 2: MAIN FORWARD LIT ────────────────────────────────────────
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.5
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma shader_feature_local _EDGEBLENDMODE_MAX _EDGEBLENDMODE_ADD _EDGEBLENDMODE_MULTIPLY
            #pragma shader_feature_local _DETAILMODE_DEPTH _DETAILMODE_CURVATURE _DETAILMODE_MANUAL

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "OvrVertexFetchBridge.hlsl"

            struct appdata
            {
                float4 vertex   : POSITION;
                float3 normal   : NORMAL;
                float4 tangent  : TANGENT;
                float2 uv       : TEXCOORD0;
                uint   vertexID : SV_VertexID;
            };

            struct v2f
            {
                float4 pos       : SV_POSITION;
                float2 uv        : TEXCOORD0;
                float3 posWS     : TEXCOORD1;
                float3 nWS       : TEXCOORD2;
                float3 viewDirWS : TEXCOORD3;
                float3 tWS       : TEXCOORD4;
                float3 bWS       : TEXCOORD5;
            };

            // ── Textures ──────────────────────────────────────────────────────
            TEXTURE2D(_MainTex);  SAMPLER(sampler_MainTex);
            TEXTURE2D(_BumpMap);  SAMPLER(sampler_BumpMap);
            TEXTURE2D(_ToonRamp); SAMPLER(sampler_ToonRamp);

            // ── Uniforms ──────────────────────────────────────────────────────
            float4 _MainTex_ST;
            float4 _Color, _RimColor, _AmbientColor, _ShadowColor;
            float4 _InnerLineColor, _OuterOutlineColor, _EdgeColor;
            float4 _LipTargetColor, _LipEdgeColor;
            float4 _BrowTargetColor, _BrowEdgeColor;

            float _BumpScale, _TextureIntensity, _ShadowStrength;
            float _LightSensitivity, _RampSmoothing, _DetailBias, _DepthNear, _DepthFar, _ManualDetail;
            float _RimPower;
            float _UseDebugDefaults, _DebugView;
            float _EnableAlphaTest, _AlphaCutoff;

            // Toggles
            float _EnableRim, _EnableTextureSobel, _EnableNormalEdges;
            float _UseLightFiltering, _UseModerateFiltering, _UseAggressiveFiltering;
            float _EnableGaussianBlur, _EnableThreshold;
            float _EnablePass1, _EnablePass2, _EnablePass3, _EnablePass4, _EnablePowerCurve;

            // Luminance Sobel params
            float _InnerLineThreshold, _InnerLineBlur, _InnerLineStrength;
            float _BlurRadiusMultiplier, _GaussianCenterWeight, _GaussianCardinalWeight, _GaussianDiagonalWeight;
            float _ThresholdMinMultiplier, _ThresholdMaxMultiplier;
            float _SmoothstepTightness, _PowerCurve;

            // Normal edge
            float _NormalEdgeThreshold, _NormalEdgeStrength, _NormalEdgeSmoothness;

            // Chromatic edge – lip
            float _EnableLipEdge;
            float _LipColorTolerance, _LipEdgeSampleDist, _LipEdgeThreshold;
            float _LipEdgeSmoothWidth, _LipEdgePower, _LipEdgeStrength;
            float _EnableSkinBoundary, _SkinColorTolerance;
            float4 _SkinTargetColor;

            // Chromatic edge – brow
            float _EnableBrowEdge;
            float _BrowColorTolerance, _BrowEdgeSampleDist, _BrowEdgeThreshold;
            float _BrowEdgeSmoothWidth, _BrowEdgePower, _BrowEdgeStrength;
            float _BrowSuppressMouth, _BrowMouthSuppressRadius, _BrowMouthSuppressStrength;

            // Wide lip Sobel
            float _EnableWideLipSobel, _LipFarOffsetScale, _LipWideCornerWeight;

            // ── Helpers ───────────────────────────────────────────────────────

            // Luminance-based 9-tap Gaussian sample (used for standard Sobel)
            float SampleLuminanceBlurred(float2 uv, float br, float cW, float kW, float dW)
            {
                float3 lc = float3(0.299, 0.587, 0.114);
                float  lum = 0.0;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv).rgb, lc) * cW;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2( br,  0)).rgb, lc) * kW;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-br,  0)).rgb, lc) * kW;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(  0, br)).rgb, lc) * kW;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(  0,-br)).rgb, lc) * kW;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2( br, br)).rgb, lc) * dW;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-br, br)).rgb, lc) * dW;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2( br,-br)).rgb, lc) * dW;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-br,-br)).rgb, lc) * dW;
                return lum;
            }

            // Returns how closely a pixel colour matches the target (0=no match, 1=exact)
            float ColorMatch(float3 col, float3 target, float tolerance)
            {
                return 1.0 - saturate(length(col - target) / max(tolerance, 0.001));
            }

            // 9-tap Gaussian on the colour-match signal (pre-blurs the mask before Sobel)
            float SampleColorMatchBlurred(float2 uv, float3 target, float tolerance,
                                          float br, float cW, float kW, float dW)
            {
                float m = 0.0;
                m += ColorMatch(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv).rgb,                    target, tolerance) * cW;
                m += ColorMatch(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2( br,  0)).rgb,  target, tolerance) * kW;
                m += ColorMatch(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-br,  0)).rgb,  target, tolerance) * kW;
                m += ColorMatch(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(  0, br)).rgb,  target, tolerance) * kW;
                m += ColorMatch(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(  0,-br)).rgb,  target, tolerance) * kW;
                m += ColorMatch(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2( br, br)).rgb,  target, tolerance) * dW;
                m += ColorMatch(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-br, br)).rgb,  target, tolerance) * dW;
                m += ColorMatch(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2( br,-br)).rgb,  target, tolerance) * dW;
                m += ColorMatch(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-br,-br)).rgb,  target, tolerance) * dW;
                return m;
            }

            // Sobel over the colour-match signal; returns the gradient vector (used for wide extension)
            float2 ChromaticSobelGrad(float2 uv, float3 target, float tolerance,
                                      float offset, float innerBr, float cW, float kW, float dW)
            {
                float tl = SampleColorMatchBlurred(uv + float2(-offset,  offset), target, tolerance, innerBr, cW, kW, dW);
                float t  = SampleColorMatchBlurred(uv + float2(      0,  offset), target, tolerance, innerBr, cW, kW, dW);
                float tr = SampleColorMatchBlurred(uv + float2( offset,  offset), target, tolerance, innerBr, cW, kW, dW);
                float l  = SampleColorMatchBlurred(uv + float2(-offset,       0), target, tolerance, innerBr, cW, kW, dW);
                float r  = SampleColorMatchBlurred(uv + float2( offset,       0), target, tolerance, innerBr, cW, kW, dW);
                float bl = SampleColorMatchBlurred(uv + float2(-offset, -offset), target, tolerance, innerBr, cW, kW, dW);
                float b  = SampleColorMatchBlurred(uv + float2(      0, -offset), target, tolerance, innerBr, cW, kW, dW);
                float br = SampleColorMatchBlurred(uv + float2( offset, -offset), target, tolerance, innerBr, cW, kW, dW);
                return float2((tr + 2.0*r + br) - (tl + 2.0*l + bl),
                              (tl + 2.0*t + tr) - (bl + 2.0*b + br));
            }

            float ChromaticSobel(float2 uv, float3 target, float tolerance,
                                  float offset, float innerBr, float cW, float kW, float dW)
            {
                float2 g = ChromaticSobelGrad(uv, target, tolerance, offset, innerBr, cW, kW, dW);
                return length(g);
            }

            // ── Paired Direction Check ──────────────────────────────────────────
            // For each opposite-neighbour pair (left↔right, up↔down, diagonals),
            // score = lipMatch(A) × skinMatch(B)  — non-zero ONLY when lip colour is
            // on one side AND skin colour is on the other.
            // Shadow-to-skin, lip-to-shadow, or shadow-to-shadow all produce 0
            // because at least one side lacks its required colour.
            float LipSkinPairedEdge(float2 uv, float offset,
                                    float3 lipColor, float lipTol,
                                    float3 skinColor, float skinTol)
            {
                float3 cR  = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2( offset,       0)).rgb;
                float3 cL  = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-offset,       0)).rgb;
                float3 cU  = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(      0,  offset)).rgb;
                float3 cD  = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(      0, -offset)).rgb;
                float3 cTR = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2( offset,  offset)).rgb;
                float3 cBL = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-offset, -offset)).rgb;
                float3 cTL = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-offset,  offset)).rgb;
                float3 cBR = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2( offset, -offset)).rgb;

                float lipR = ColorMatch(cR,  lipColor, lipTol);   float skinR = ColorMatch(cR,  skinColor, skinTol);
                float lipL = ColorMatch(cL,  lipColor, lipTol);   float skinL = ColorMatch(cL,  skinColor, skinTol);
                float lipU = ColorMatch(cU,  lipColor, lipTol);   float skinU = ColorMatch(cU,  skinColor, skinTol);
                float lipD = ColorMatch(cD,  lipColor, lipTol);   float skinD = ColorMatch(cD,  skinColor, skinTol);
                float lipTR= ColorMatch(cTR, lipColor, lipTol);   float skinTR= ColorMatch(cTR, skinColor, skinTol);
                float lipBL= ColorMatch(cBL, lipColor, lipTol);   float skinBL= ColorMatch(cBL, skinColor, skinTol);
                float lipTL= ColorMatch(cTL, lipColor, lipTol);   float skinTL= ColorMatch(cTL, skinColor, skinTol);
                float lipBR= ColorMatch(cBR, lipColor, lipTol);   float skinBR= ColorMatch(cBR, skinColor, skinTol);

                float e = 0.0;
                e = max(e, max(lipR * skinL,  lipL * skinR ));  // horizontal
                e = max(e, max(lipU * skinD,  lipD * skinU ));  // vertical
                e = max(e, max(lipTR* skinBL, lipBL* skinTR));  // diagonal
                e = max(e, max(lipTL* skinBR, lipBR* skinTL));  // anti-diagonal
                return e;
            }

            // 9-tap blurred (lipMatch − skinMatch).
            // Positive inside the lip region, negative inside the skin region;
            // Sobel on this signal fires only at the lip-to-skin boundary, not at
            // lip-to-shadow or shadow-to-skin transitions.
            float SampleLipSkinDiff(float2 uv, float br, float cW, float kW, float dW)
            {
                float3 col;
                float  result = 0.0;
                col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv).rgb;
                result += (ColorMatch(col, _LipTargetColor.rgb, _LipColorTolerance) - ColorMatch(col, _SkinTargetColor.rgb, _SkinColorTolerance)) * cW;
                col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2( br,  0)).rgb;
                result += (ColorMatch(col, _LipTargetColor.rgb, _LipColorTolerance) - ColorMatch(col, _SkinTargetColor.rgb, _SkinColorTolerance)) * kW;
                col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-br,  0)).rgb;
                result += (ColorMatch(col, _LipTargetColor.rgb, _LipColorTolerance) - ColorMatch(col, _SkinTargetColor.rgb, _SkinColorTolerance)) * kW;
                col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(  0, br)).rgb;
                result += (ColorMatch(col, _LipTargetColor.rgb, _LipColorTolerance) - ColorMatch(col, _SkinTargetColor.rgb, _SkinColorTolerance)) * kW;
                col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(  0,-br)).rgb;
                result += (ColorMatch(col, _LipTargetColor.rgb, _LipColorTolerance) - ColorMatch(col, _SkinTargetColor.rgb, _SkinColorTolerance)) * kW;
                col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2( br, br)).rgb;
                result += (ColorMatch(col, _LipTargetColor.rgb, _LipColorTolerance) - ColorMatch(col, _SkinTargetColor.rgb, _SkinColorTolerance)) * dW;
                col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-br, br)).rgb;
                result += (ColorMatch(col, _LipTargetColor.rgb, _LipColorTolerance) - ColorMatch(col, _SkinTargetColor.rgb, _SkinColorTolerance)) * dW;
                col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2( br,-br)).rgb;
                result += (ColorMatch(col, _LipTargetColor.rgb, _LipColorTolerance) - ColorMatch(col, _SkinTargetColor.rgb, _SkinColorTolerance)) * dW;
                col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-br,-br)).rgb;
                result += (ColorMatch(col, _LipTargetColor.rgb, _LipColorTolerance) - ColorMatch(col, _SkinTargetColor.rgb, _SkinColorTolerance)) * dW;
                return result;
            }

            // Unified lip sampler: switches between lip-only mask and lip-skin-diff
            // depending on _EnableSkinBoundary — used by both main Sobel and wide corners
            float SampleLipSignal(float2 uv, float br, float cW, float kW, float dW)
            {
                if (_EnableSkinBoundary > 0.5)
                    return SampleLipSkinDiff(uv, br, cW, kW, dW);
                return SampleColorMatchBlurred(uv, _LipTargetColor.rgb, _LipColorTolerance, br, cW, kW, dW);
            }

            // Sobel gradient over the lip signal (respects _EnableSkinBoundary automatically)
            float2 LipSobelGrad(float2 uv, float offset, float innerBr, float cW, float kW, float dW)
            {
                float tl = SampleLipSignal(uv + float2(-offset,  offset), innerBr, cW, kW, dW);
                float t  = SampleLipSignal(uv + float2(      0,  offset), innerBr, cW, kW, dW);
                float tr = SampleLipSignal(uv + float2( offset,  offset), innerBr, cW, kW, dW);
                float l  = SampleLipSignal(uv + float2(-offset,       0), innerBr, cW, kW, dW);
                float r  = SampleLipSignal(uv + float2( offset,       0), innerBr, cW, kW, dW);
                float bl = SampleLipSignal(uv + float2(-offset, -offset), innerBr, cW, kW, dW);
                float b  = SampleLipSignal(uv + float2(      0, -offset), innerBr, cW, kW, dW);
                float br = SampleLipSignal(uv + float2( offset, -offset), innerBr, cW, kW, dW);
                return float2((tr + 2.0*r + br) - (tl + 2.0*l + bl),
                              (tl + 2.0*t + tr) - (bl + 2.0*b + br));
            }

            // Max lip-colour match across a 9-tap neighbourhood — detects mouth proximity
            float MouthProximity(float2 uv, float radius, float3 lipColor, float lipTol)
            {
                float mx = 0.0;
                mx = max(mx, ColorMatch(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv).rgb,                           lipColor, lipTol));
                mx = max(mx, ColorMatch(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2( radius,      0)).rgb,  lipColor, lipTol));
                mx = max(mx, ColorMatch(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-radius,      0)).rgb,  lipColor, lipTol));
                mx = max(mx, ColorMatch(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(      0,  radius)).rgb, lipColor, lipTol));
                mx = max(mx, ColorMatch(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(      0, -radius)).rgb, lipColor, lipTol));
                mx = max(mx, ColorMatch(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2( radius,  radius)).rgb, lipColor, lipTol));
                mx = max(mx, ColorMatch(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-radius,  radius)).rgb, lipColor, lipTol));
                mx = max(mx, ColorMatch(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2( radius, -radius)).rgb, lipColor, lipTol));
                mx = max(mx, ColorMatch(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-radius, -radius)).rgb, lipColor, lipTol));
                return mx;
            }

            // Applies threshold → single smoothstep → power curve to a raw edge magnitude
            float ShapeEdge(float rawMag, float threshold, float smoothWidth, float powerCurve)
            {
                float edge = smoothstep(threshold - smoothWidth * 0.5,
                                        threshold + smoothWidth * 0.5, rawMag);
                return pow(saturate(edge), max(powerCurve, 0.01));
            }

            // ── Vertex ────────────────────────────────────────────────────────
            v2f vert(appdata v)
            {
                v2f o;
                OVR_FETCH_POS_NORM(v.vertex.xyz, v.normal, v.vertexID);
                VertexPositionInputs posInputs  = GetVertexPositionInputs(v.vertex.xyz);
                VertexNormalInputs   normInputs = GetVertexNormalInputs(v.normal, v.tangent);
                o.pos       = posInputs.positionCS;
                o.uv        = TRANSFORM_TEX(v.uv, _MainTex);
                o.posWS     = posInputs.positionWS;
                o.nWS       = normInputs.normalWS;
                o.viewDirWS = GetWorldSpaceViewDir(posInputs.positionWS);
                o.tWS       = normInputs.tangentWS;
                o.bWS       = normInputs.bitangentWS;
                return o;
            }

            // ── Fragment ──────────────────────────────────────────────────────
            half4 frag(v2f IN) : SV_Target
            {
                float textureIntensity = _TextureIntensity;
                float shadowStrength   = _ShadowStrength;
                float rimPower         = _RimPower;

                if (_UseDebugDefaults > 0.5)
                {
                    textureIntensity = 1.0;
                    shadowStrength   = 0.6;
                    rimPower         = 5.0;
                }

                half4 texColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);
                if (_EnableAlphaTest > 0.5) clip(texColor.a - _AlphaCutoff);

                half3 baseColor = lerp(_Color.rgb, texColor.rgb * _Color.rgb, textureIntensity);
                half4 albedo    = half4(baseColor, texColor.a * _Color.a);

                // GLTFast GLB normal map – raw RGB, NOT DXT5nm
                half3 normalTS = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, IN.uv).rgb * 2.0h - 1.0h;
                normalTS.xy   *= _BumpScale;
                normalTS        = normalize(normalTS);
                float3x3 TBN   = float3x3(normalize(IN.tWS), normalize(IN.bWS), normalize(IN.nWS));
                float3 nWS     = normalize(mul(normalTS, TBN));
                float3 vWS     = normalize(IN.viewDirWS);

                int debugMode = (int)_DebugView;

                // ═══ GAUSSIAN BLUR WEIGHTS (shared by all Sobel passes) ═══════
                float blurRadiusMult = _BlurRadiusMultiplier;
                float gaussCW = _GaussianCenterWeight;
                float gaussKW = _GaussianCardinalWeight;
                float gaussDW = _GaussianDiagonalWeight;
                float threshMinMult = _ThresholdMinMultiplier;
                float threshMaxMult = _ThresholdMaxMultiplier;
                float smoothTight   = _SmoothstepTightness;
                float powerCurve    = _PowerCurve;

                if (_UseLightFiltering > 0.5)
                { blurRadiusMult=0.8; gaussCW=0.25; gaussKW=0.125; gaussDW=0.0625; threshMinMult=0.2; threshMaxMult=2.0; smoothTight=0.2; powerCurve=1.5; }
                if (_UseModerateFiltering > 0.5)
                { blurRadiusMult=1.0; gaussCW=0.3;  gaussKW=0.12;  gaussDW=0.05;   threshMinMult=0.4; threshMaxMult=1.6; smoothTight=0.3; powerCurve=2.0; }
                if (_UseAggressiveFiltering > 0.5)
                { blurRadiusMult=1.2; gaussCW=0.25; gaussKW=0.125; gaussDW=0.0625; threshMinMult=0.85; threshMaxMult=1.15; smoothTight=1.0; powerCurve=3.0; }

                // Normalise Gaussian weights
                float totalW = gaussCW + 4.0*gaussKW + 4.0*gaussDW;
                float cW = gaussCW / totalW;
                float kW = gaussKW / totalW;
                float dW = gaussDW / totalW;
                if (_EnableGaussianBlur < 0.5) { cW=1.0; kW=0.0; dW=0.0; }

                // ═══ LUMINANCE SOBEL EDGE ════════════════════════════════════
                float sobelEdge       = 0.0;
                float debugRawSobel   = 0.0;
                float debugAfterThresh = 0.0;
                float debugAfterBlur  = 0.0;

                if (_EnableTextureSobel > 0.5)
                {
                    float offset     = _InnerLineBlur * 0.001;
                    float blurOffset = (_EnableGaussianBlur > 0.5) ? offset * blurRadiusMult : 0.0;

                    float tl = SampleLuminanceBlurred(IN.uv + float2(-offset,  offset), blurOffset, cW, kW, dW);
                    float t  = SampleLuminanceBlurred(IN.uv + float2(      0,  offset), blurOffset, cW, kW, dW);
                    float tr = SampleLuminanceBlurred(IN.uv + float2( offset,  offset), blurOffset, cW, kW, dW);
                    float l  = SampleLuminanceBlurred(IN.uv + float2(-offset,       0), blurOffset, cW, kW, dW);
                    float r  = SampleLuminanceBlurred(IN.uv + float2( offset,       0), blurOffset, cW, kW, dW);
                    float bl = SampleLuminanceBlurred(IN.uv + float2(-offset, -offset), blurOffset, cW, kW, dW);
                    float b  = SampleLuminanceBlurred(IN.uv + float2(      0, -offset), blurOffset, cW, kW, dW);
                    float br = SampleLuminanceBlurred(IN.uv + float2( offset, -offset), blurOffset, cW, kW, dW);

                    float sX    = (tr + 2.0*r + br) - (tl + 2.0*l + bl);
                    float sY    = (tl + 2.0*t + tr) - (bl + 2.0*b + br);
                    float eMag  = sqrt(sX*sX + sY*sY);
                    debugRawSobel = eMag;

                    float edge = eMag;
                    if (_EnableThreshold > 0.5)
                    {
                        float minE = _InnerLineThreshold * threshMinMult;
                        float maxE = _InnerLineThreshold * threshMaxMult;
                        edge = smoothstep(minE, maxE, eMag);
                    }
                    debugAfterThresh = edge;

                    float tight = smoothTight;
                    if (_EnablePass1 > 0.5) { float hw=lerp(0.5,0.03,tight); edge=smoothstep(0.5-hw,0.5+hw,edge); }
                    if (_EnablePass2 > 0.5) { float hw=lerp(0.5,0.15,tight); edge=smoothstep(0.5-hw,0.5+hw,edge); }
                    if (_EnablePass3 > 0.5) { float hw=lerp(0.5,0.25,tight); edge=smoothstep(0.5-hw,0.5+hw,edge); }
                    if (_EnablePass4 > 0.5) { float hw=lerp(0.5,0.35,tight); edge=smoothstep(0.5-hw,0.5+hw,edge); }
                    if (_EnablePowerCurve > 0.5) edge = pow(edge, powerCurve);
                    debugAfterBlur = edge;

                    sobelEdge = edge * _InnerLineStrength;
                }

                // ═══ NORMAL EDGE ═════════════════════════════════════════════
                float normalEdge = 0.0;
                if (_EnableNormalEdges > 0.5)
                {
                    float nVar = length(ddx(nWS)) + length(ddy(nWS));
                    normalEdge = smoothstep(_NormalEdgeThreshold - _NormalEdgeSmoothness,
                                            _NormalEdgeThreshold + _NormalEdgeSmoothness,
                                            nVar) * _NormalEdgeStrength;
                }

                // ═══ STANDARD COMBINED EDGE ══════════════════════════════════
                float combinedEdge = 0.0;
                #if defined(_EDGEBLENDMODE_ADD)
                    combinedEdge = saturate(sobelEdge + normalEdge);
                #elif defined(_EDGEBLENDMODE_MULTIPLY)
                    float hasE = step(0.001, sobelEdge + normalEdge);
                    combinedEdge = hasE * saturate(max(sobelEdge,0.001)*max(normalEdge+1.0,1.0)-1.0);
                #else
                    combinedEdge = max(sobelEdge, normalEdge);
                #endif

                // ═══ CHROMATIC EDGE: LIP LINE ════════════════════════════════
                float lipMask = 0.0;
                float lipEdge = 0.0;

                if (_EnableLipEdge > 0.5)
                {
                    float lipOffset  = _LipEdgeSampleDist * 0.001;
                    float lipInnerBr = (_EnableGaussianBlur > 0.5) ? lipOffset * blurRadiusMult : 0.0;

                    lipMask = ColorMatch(texColor.rgb, _LipTargetColor.rgb, _LipColorTolerance);

                    float rawLip;

                    if (_EnableSkinBoundary > 0.5)
                    {
                        // ── Paired direction check ─────────────────────────────
                        // score(pair) = lipMatch(A) × skinMatch(B)
                        // Zero whenever lip or skin is absent on either side.
                        // Shadow gradients, cheek colour shifts, under-eye tones
                        // all produce 0 because they lack a lip neighbour.
                        rawLip = LipSkinPairedEdge(IN.uv, lipOffset,
                                                   _LipTargetColor.rgb, _LipColorTolerance,
                                                   _SkinTargetColor.rgb, _SkinColorTolerance);

                        // Wide mode: also check at a further offset and take the max
                        if (_EnableWideLipSobel > 0.5)
                        {
                            float farOff = lipOffset * _LipFarOffsetScale;
                            float rawFar = LipSkinPairedEdge(IN.uv, farOff,
                                                             _LipTargetColor.rgb, _LipColorTolerance,
                                                             _SkinTargetColor.rgb, _SkinColorTolerance);
                            rawLip = max(rawLip, rawFar * _LipWideCornerWeight);
                        }
                    }
                    else
                    {
                        // ── Original Sobel on lip-mask (kept for comparison) ───
                        float2 lipGrad = LipSobelGrad(IN.uv, lipOffset, lipInnerBr, cW, kW, dW);

                        if (_EnableWideLipSobel > 0.5)
                        {
                            float farOff = lipOffset * _LipFarOffsetScale;
                            float ftl = SampleLipSignal(IN.uv + float2(-farOff,  farOff), lipInnerBr, cW, kW, dW);
                            float ftr = SampleLipSignal(IN.uv + float2( farOff,  farOff), lipInnerBr, cW, kW, dW);
                            float fbl = SampleLipSignal(IN.uv + float2(-farOff, -farOff), lipInnerBr, cW, kW, dW);
                            float fbr = SampleLipSignal(IN.uv + float2( farOff, -farOff), lipInnerBr, cW, kW, dW);
                            lipGrad.x += _LipWideCornerWeight * ((ftr + fbr) - (ftl + fbl));
                            lipGrad.y += _LipWideCornerWeight * ((ftl + ftr) - (fbl + fbr));
                        }

                        rawLip = length(lipGrad);
                    }

                    lipEdge = ShapeEdge(rawLip, _LipEdgeThreshold, _LipEdgeSmoothWidth, _LipEdgePower)
                              * _LipEdgeStrength;
                }

                // ═══ CHROMATIC EDGE: EYEBROW ═════════════════════════════════
                float browMask        = 0.0;
                float browEdge        = 0.0;
                float browSuppressMap = 0.0;

                // Mouth proximity map — built whenever suppression is active or debug view 9 is selected
                // Uses _LipTargetColor as the mouth colour reference (set that picker even when lip edge is off)
                if (_BrowSuppressMouth > 0.5 || debugMode == 9)
                {
                    float suppR = _BrowMouthSuppressRadius * 0.001;
                    browSuppressMap = MouthProximity(IN.uv, suppR, _LipTargetColor.rgb, _LipColorTolerance);
                }

                if (_EnableBrowEdge > 0.5)
                {
                    float browOffset  = _BrowEdgeSampleDist * 0.001;
                    float browInnerBr = (_EnableGaussianBlur > 0.5) ? browOffset * blurRadiusMult : 0.0;

                    browMask = ColorMatch(texColor.rgb, _BrowTargetColor.rgb, _BrowColorTolerance);

                    float rawBrow = ChromaticSobel(IN.uv,
                                                   _BrowTargetColor.rgb, _BrowColorTolerance,
                                                   browOffset, browInnerBr, cW, kW, dW);
                    browEdge = ShapeEdge(rawBrow, _BrowEdgeThreshold, _BrowEdgeSmoothWidth, _BrowEdgePower)
                               * _BrowEdgeStrength;

                    // Suppress wherever mouth-coloured pixels appear nearby
                    if (_BrowSuppressMouth > 0.5)
                        browEdge *= 1.0 - saturate(browSuppressMap * _BrowMouthSuppressStrength);
                }

                // ═══ DEBUG VIEWS ═════════════════════════════════════════════
                if (debugMode == 1) return half4(debugRawSobel.xxx, 1.0);
                if (debugMode == 2) return half4(debugAfterThresh.xxx, 1.0);
                if (debugMode == 3) return half4(debugAfterBlur.xxx, 1.0);
                if (debugMode == 4) return half4(normalEdge.xxx, 1.0);
                if (debugMode == 5) return half4(lipMask.xxx, 1.0);
                if (debugMode == 6) return half4(lipEdge.xxx, 1.0);
                if (debugMode == 7) return half4(browMask.xxx, 1.0);
                if (debugMode == 8) return half4(browEdge.xxx, 1.0);
                if (debugMode == 9) return half4(browSuppressMap.xxx, 1.0);
                float skinMatch = ColorMatch(texColor.rgb, _SkinTargetColor.rgb, _SkinColorTolerance);
                if (debugMode == 10) return half4(skinMatch.xxx, 1.0);

                // ═══ XTOON 2D RAMP SHADING ═══════════════════════════════════
                Light mainLight = GetMainLight();
                float3 lightDir = normalize(mainLight.direction);
                float NdotL     = dot(nWS, lightDir);
                float rampU     = lerp(0.5, saturate(NdotL * 0.5 + 0.5), _LightSensitivity);
                float rampV;

                #if defined(_DETAILMODE_CURVATURE)
                    float curv = length(ddx(nWS)) + length(ddy(nWS));
                    rampV = saturate((1.0 - saturate(curv * 10.0)) * (1.0 - _DetailBias) + _DetailBias);
                #elif defined(_DETAILMODE_MANUAL)
                    rampV = saturate(_ManualDetail);
                #else
                    float depth = length(_WorldSpaceCameraPos - IN.posWS);
                    rampV = saturate(saturate((depth - _DepthNear) / max(0.001, _DepthFar - _DepthNear)) + _DetailBias);
                #endif

                float3 rampColor  = SAMPLE_TEXTURE2D(_ToonRamp, sampler_ToonRamp, float2(rampU, rampV)).rgb;
                float  adjU       = lerp(rampU, 0.5, rampV * 0.6);
                float  dynSmooth  = lerp(_RampSmoothing, _RampSmoothing + 0.35, rampV);
                float  shadowMask = smoothstep(0.5 - dynSmooth, 0.5 + dynSmooth, adjU);

                float3 toonBase    = albedo.rgb * rampColor;
                float3 shadowedBase = lerp(toonBase * _ShadowColor.rgb, toonBase, shadowMask);
                float3 shaded      = lerp(albedo.rgb, shadowedBase, shadowStrength);
                shaded            += _AmbientColor.rgb * albedo.rgb;

                if (_EnableRim > 0.5)
                {
                    float rim = pow(1.0 - saturate(dot(vWS, nWS)), rimPower);
                    shaded += rim * _RimColor.rgb;
                }

                // ═══ COMPOSITE EDGES ═════════════════════════════════════════
                // Layer order: base shading → standard Sobel/normal → lip line → brow
                float3 edgeColor = (_EnableTextureSobel > 0.5 && _EnableNormalEdges < 0.5)
                                   ? _InnerLineColor.rgb : _EdgeColor.rgb;
                shaded = lerp(shaded, edgeColor, combinedEdge);
                shaded = lerp(shaded, _LipEdgeColor.rgb,  lipEdge);
                shaded = lerp(shaded, _BrowEdgeColor.rgb, browEdge);

                return half4(shaded, albedo.a);
            }
            ENDHLSL
        }

        // ─── PASS 3: DEPTH NORMALS ────────────────────────────────────────────
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }
            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma vertex   DNVert
            #pragma fragment DNFrag
            #pragma target   3.5
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);
            float4 _MainTex_ST;
            float  _BumpScale;

            struct DNAttr
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
            };
            struct DNVary
            {
                float4 positionCS  : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float3 tangentWS   : TEXCOORD2;
                float3 bitangentWS : TEXCOORD3;
            };

            DNVary DNVert(DNAttr v)
            {
                DNVary o;
                VertexPositionInputs pi = GetVertexPositionInputs(v.positionOS.xyz);
                VertexNormalInputs   ni = GetVertexNormalInputs(v.normalOS, v.tangentOS);
                o.positionCS  = pi.positionCS;
                o.uv          = TRANSFORM_TEX(v.uv, _MainTex);
                o.normalWS    = ni.normalWS;
                o.tangentWS   = ni.tangentWS;
                o.bitangentWS = ni.bitangentWS;
                return o;
            }

            float4 DNFrag(DNVary i) : SV_Target
            {
                half3 nTS    = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.uv).rgb * 2.0h - 1.0h;
                nTS.xy      *= _BumpScale;
                nTS           = normalize(nTS);
                float3x3 TBN = float3x3(normalize(i.tangentWS),
                                        normalize(i.bitangentWS),
                                        normalize(i.normalWS));
                float3 nWS   = normalize(mul(nTS, TBN));
                return half4(NormalizeNormalPerPixel(nWS), 0.0);
            }
            ENDHLSL
        }
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    CustomEditor "AvaturnPresetShaderGUI"
}
