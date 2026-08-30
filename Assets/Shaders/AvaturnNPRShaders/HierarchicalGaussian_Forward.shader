// V5 — Hierarchical Edge Detection with Gaussian Pre-blur  (Avaturn variant)
// Identical algorithm to the Jade V5, extended with:
//   • Normal map (TBN) in ForwardLit
//   • DepthNormals pass so the shared post-process EdgeDetectionFeature
//     receives normal-map-perturbed normals from the Avaturn mesh
//   • OVR vertex fetch bridge for Meta SDK skinning compatibility

Shader "Custom/Avaturn_HierarchicalGaussian_Forward"
{
    Properties
    {
        [Header(Base)]
        _MainTex          ("Albedo Texture",   2D)         = "white" {}
        _Color            ("Main Color",       Color)      = (1,1,1,1)
        _TextureIntensity ("Texture Intensity",Range(0,1)) = 1.0

        [Normal]
        _BumpMap  ("Normal Map",      2D)         = "bump" {}
        _BumpScale("Normal Intensity",Range(0,2)) = 1.0

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
        _AmbientColor   ("Ambient Color",   Color)        = (0.35,0.35,0.35,1)
        [Toggle] _EnableRim ("Enable Rim Lighting", Float) = 1
        _RimColor       ("Rim Color",       Color)        = (0.408,0.408,0.408,1)
        _RimPower       ("Rim Power",       Range(0.5,10))= 3.0

        [Header(Outer Outline)]
        _OuterOutlineWidth ("Outline Width", Range(0,0.05)) = 0.002
        _OuterOutlineColor ("Outline Color", Color)         = (0,0,0,1)

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

        [Header(Skin Discard on Color Layer)]
        [Toggle] _HEnableSkinDiscard ("Suppress color edges on skin", Float) = 0
        _HSkinHueMin ("Skin Hue Min",        Range(0,0.2))  = 0.02
        _HSkinHueMax ("Skin Hue Max",        Range(0,0.2))  = 0.12
        _HSkinSatMin ("Skin Saturation Min", Range(0,0.5))  = 0.15

        [Header(Edge Output)]
        _HEdgeColor        ("Edge Color",       Color)      = (0,0,0,1)
        _HEdgeStrength     ("Edge Strength",    Range(0,1)) = 1.0
        _HAdaptiveStrength ("Adaptive Strength",Range(0,1)) = 0.5

        [Header(Alpha Test)]
        [Toggle] _EnableAlphaTest ("Alpha Test (eyelashes)", Float) = 0
        _AlphaCutoff ("Alpha Cutoff", Range(0,1)) = 0.07
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        // ── Outer outline (inverted hull) ────────────────────────────────────
        Pass
        {
            Name "OuterOutline"
            Tags { "Queue"="Geometry+1" }
            Cull Front
            ZWrite On
            ZTest Less

            HLSLPROGRAM
            #pragma vertex   vert_ol
            #pragma fragment frag_ol
            #pragma target   3.5
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "OvrVertexFetchBridge.hlsl"

            struct Attr_OL { float4 vertex : POSITION; float3 normal : NORMAL; float2 uv : TEXCOORD0; uint vertexID : SV_VertexID; };
            struct Vary_OL { float4 pos    : SV_POSITION; float2 uv  : TEXCOORD0; };

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _Color, _AmbientColor, _RimColor, _HEdgeColor, _OuterOutlineColor;
                float  _TextureIntensity, _BumpScale, _ShadowStrength, _RimPower, _EnableRim;
                float  _OuterOutlineWidth;
                float  _EnableAlphaTest, _AlphaCutoff;
                float  _EnableDepthEdge,  _HDepthThreshold,  _HDepthWeight, _HDepthScale;
                float  _EnableNormalEdge, _HNormalThreshold, _HNormalWeight;
                float  _EnableColorEdge,  _HColorThreshold,  _HColorWeight, _HEdgeWidth;
                float  _EnableGaussBlur,  _HBlurRadius;
                float  _HCenterWeight, _HCardinalWeight, _HDiagonalWeight;
                float  _HXDoGK, _HXDoGTau, _HXDoGPhi;
                float  _HEdgeStrength, _HAdaptiveStrength;
                float  _HEnableSkinDiscard, _HSkinHueMin, _HSkinHueMax, _HSkinSatMin;
                float4 _ShadowColor;
                float  _LightSensitivity, _RampSmoothing, _DetailBias, _DepthNear, _DepthFar, _ManualDetail;
            CBUFFER_END

            Vary_OL vert_ol(Attr_OL v)
            {
                OVR_FETCH_POS_NORM(v.vertex.xyz, v.normal, v.vertexID);
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
            #pragma target   3.5
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma shader_feature_local _DETAILMODE_DEPTH _DETAILMODE_CURVATURE _DETAILMODE_MANUAL

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "OvrVertexFetchBridge.hlsl"

            struct Attr
            {
                float4 vertex   : POSITION;
                float3 normal   : NORMAL;
                float4 tangent  : TANGENT;
                float2 uv       : TEXCOORD0;
                uint   vertexID : SV_VertexID;
            };

            struct Vary
            {
                float4 pos   : SV_POSITION;
                float2 uv    : TEXCOORD0;
                float3 posWS : TEXCOORD1;
                float3 nWS   : TEXCOORD2;
                float3 tWS   : TEXCOORD3;
                float3 bWS   : TEXCOORD4;
            };

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);
            TEXTURE2D(_ToonRamp); SAMPLER(sampler_ToonRamp);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _Color, _AmbientColor, _RimColor, _HEdgeColor, _OuterOutlineColor;
                float  _TextureIntensity, _BumpScale, _ShadowStrength, _RimPower, _EnableRim;
                float  _OuterOutlineWidth;
                float  _EnableAlphaTest, _AlphaCutoff;
                float  _EnableDepthEdge,  _HDepthThreshold,  _HDepthWeight, _HDepthScale;
                float  _EnableNormalEdge, _HNormalThreshold, _HNormalWeight;
                float  _EnableColorEdge,  _HColorThreshold,  _HColorWeight, _HEdgeWidth;
                float  _EnableGaussBlur,  _HBlurRadius;
                float  _HCenterWeight, _HCardinalWeight, _HDiagonalWeight;
                float  _HXDoGK, _HXDoGTau, _HXDoGPhi;
                float  _HEdgeStrength, _HAdaptiveStrength;
                float  _HEnableSkinDiscard, _HSkinHueMin, _HSkinHueMax, _HSkinSatMin;
                float4 _ShadowColor;
                float  _LightSensitivity, _RampSmoothing, _DetailBias, _DepthNear, _DepthFar, _ManualDetail;
            CBUFFER_END

            static const float3 LUMA = float3(0.2126, 0.7152, 0.0722);

            float3 RGBtoHSV(float3 c)
            {
                float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
                float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
                float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
                float  d = q.x - min(q.w, q.y);
                return float3(abs(q.z + (q.w - q.y) / (6.0*d + 1e-10)),
                              d / (q.x + 1e-10), q.x);
            }

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
                OVR_FETCH_POS_NORM(v.vertex.xyz, v.normal, v.vertexID);
                Vary o;
                VertexPositionInputs pi = GetVertexPositionInputs(v.vertex.xyz);
                VertexNormalInputs   ni = GetVertexNormalInputs(v.normal, v.tangent);
                o.pos   = pi.positionCS;
                o.uv    = TRANSFORM_TEX(v.uv, _MainTex);
                o.posWS = pi.positionWS;
                o.nWS   = ni.normalWS;
                o.tWS   = ni.tangentWS;
                o.bWS   = ni.bitangentWS;
                return o;
            }

            half4 frag(Vary IN) : SV_Target
            {
                half4 texColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);
                if (_EnableAlphaTest > 0.5) clip(texColor.a - _AlphaCutoff);

                half3 baseColor = lerp(_Color.rgb, texColor.rgb * _Color.rgb, _TextureIntensity);
                half4 albedo    = half4(baseColor, texColor.a * _Color.a);

                // Geometric vertex normal — used for edge detection (robust on all meshes).
                float3 geoNWS = normalize(IN.nWS);

                // Normal map → world-space normal — used only for lighting.
                // GLTFast GLB sub-assets are raw-RGB normal maps — decode as plain RGB.
                half3 normalTS = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, IN.uv).rgb * 2.0h - 1.0h;
                normalTS.xy   *= _BumpScale;
                normalTS        = normalize(normalTS);
                float3x3 TBN = float3x3(normalize(IN.tWS), normalize(IN.bWS), geoNWS);
                float3 nWS   = normalize(mul(normalTS, TBN));

                float3 vWS = normalize(_WorldSpaceCameraPos - IN.posWS);

                // XToon 2D Ramp Shading + rim
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
                    float rim = pow(1.0 - saturate(dot(vWS, nWS)), _RimPower);
                    shaded += rim * _RimColor.rgb;
                }

                // ── Layer 1: Depth proxy (perspective-normalised distance gradient) ──
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

                // ── Layer 2: Normal discontinuity (geometric vertex normal) ──────
                float normalLine = 0.0;
                if (_EnableNormalEdge > 0.5)
                {
                    float3 dNdx = ddx(geoNWS);
                    float3 dNdy = ddy(geoNWS);
                    float  edge = sqrt(dot(dNdx, dNdx) + dot(dNdy, dNdy));
                    normalLine  = smoothstep(_HNormalThreshold - 0.02,
                                             _HNormalThreshold + 0.02, edge);
                }

                // ── Layer 3: XDoG texture edge (Difference of Gaussians) ──────
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
                    colorLine = D < -_HColorThreshold
                        ? saturate(-tanh(_HXDoGPhi * (D + _HColorThreshold)))
                        : 0.0;

                    if (_HEnableSkinDiscard > 0.5)
                    {
                        float3 hsv = RGBtoHSV(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv).rgb);
                        if (hsv.x >= _HSkinHueMin && hsv.x <= _HSkinHueMax && hsv.y >= _HSkinSatMin)
                            colorLine = 0.0;
                    }
                }

                // ── Weighted max-pooling + AHEAD adaptive gain (normal layer only) ────
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

        // ── DepthNormals — writes normal-map-perturbed normals to URP's
        //    _CameraNormalsTexture so the shared post-process EdgeDetectionFeature
        //    sees bump-map detail from the Avaturn mesh.
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma vertex   DNVert
            #pragma fragment DNFrag
            #pragma target   3.5

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _Color, _AmbientColor, _RimColor, _HEdgeColor, _OuterOutlineColor;
                float  _TextureIntensity, _BumpScale, _ShadowStrength, _RimPower, _EnableRim;
                float  _OuterOutlineWidth;
                float  _EnableAlphaTest, _AlphaCutoff;
                float  _EnableDepthEdge,  _HDepthThreshold,  _HDepthWeight, _HDepthScale;
                float  _EnableNormalEdge, _HNormalThreshold, _HNormalWeight;
                float  _EnableColorEdge,  _HColorThreshold,  _HColorWeight, _HEdgeWidth;
                float  _EnableGaussBlur,  _HBlurRadius;
                float  _HCenterWeight, _HCardinalWeight, _HDiagonalWeight;
                float  _HXDoGK, _HXDoGTau, _HXDoGPhi;
                float  _HEdgeStrength, _HAdaptiveStrength;
                float  _HEnableSkinDiscard, _HSkinHueMin, _HSkinHueMax, _HSkinSatMin;
                float4 _ShadowColor;
                float  _LightSensitivity, _RampSmoothing, _DetailBias, _DepthNear, _DepthFar, _ManualDetail;
            CBUFFER_END

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
