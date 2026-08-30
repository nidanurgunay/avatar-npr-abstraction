// Version 3: Basic Sobel Edge Detection (NO PRE-BLUR) – Avaturn Edition
// Structurally aligned with V4; simple step-based Sobel is its unique feature.
// Includes normal-map support and DepthNormals pass for screen-space normal writing.

Shader "Custom/SobelEdgeDetection"
{
    Properties
    {
        [Header(DEBUG AND VISUALIZATION)]
        [Toggle] _UseDebugDefaults ("Use Debug Defaults", Float) = 0
        [KeywordEnum(Final, RawSobel, AfterThreshold, AfterBlur, NormalEdge, FresnelEdge)] _DebugView ("Debug View", Float) = 0
        [Space(10)]

        [Header(Base)]
        _Color ("Main Color", Color) = (1,1,1,1)
        _MainTex ("Albedo Texture", 2D) = "white" {}
        _TextureIntensity ("Texture Intensity", Range(0,1)) = 1.0

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
        _OuterOutlineWidth ("Outer Outline Width", Range(0,0.5)) = 0.005
        _OuterOutlineColor ("Outline Color", Color) = (0,0,0,1)
        [Toggle] _UseOutlineDepthOffset ("Use Depth Offset", Float) = 0
        _OutlineDepthBias ("Outline Depth Bias", Range(0,5)) = 1.0

        [Header(Inner Lines Sobel)]
        [Toggle] _EnableInnerLines ("Enable Inner Lines", Float) = 1
        _InnerLineColor ("Inner Line Color", Color) = (0,0,0,1)
        _InnerLineThreshold ("Inner Line Threshold", Range(0.001,0.5)) = 0.2
        _InnerLineBlur ("Inner Line Sample Distance", Range(0.0,10.0)) = 0.5
        _InnerLineStrength ("Inner Line Strength", Range(0,1)) = 1.0

        [Header(Rim and Ambient)]
        [Toggle] _EnableRim ("Enable Rim Lighting", Float) = 1
        _RimColor ("Rim Color", Color) = (0.408,0.408,0.408,1)
        _RimPower ("Rim Power", Range(0.1,8.0)) = 3.0
        _AmbientColor ("Ambient Color", Color) = (0.35,0.35,0.35,1)

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
            Cull Front
            ZWrite On
            ZTest Less

            HLSLPROGRAM
            #pragma vertex   vert_outline
            #pragma fragment frag_outline
            #pragma target   3.5
            #pragma shader_feature_local _USEOUTLINEDEPTHOFFSET_ON
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "OvrVertexFetchBridge.hlsl"

            struct Attr_OL { float4 vertex : POSITION; float3 normal : NORMAL; float2 uv : TEXCOORD0; uint vertexID : SV_VertexID; };
            struct Vary_OL { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            float4 _MainTex_ST;
            float4 _OuterOutlineColor;
            float  _OuterOutlineWidth;
            float  _EnableAlphaTest;
            float  _AlphaCutoff;
            float  _OutlineDepthBias;

            Vary_OL vert_outline(Attr_OL v)
            {
                Vary_OL o;
                OVR_FETCH_POS_NORM(v.vertex.xyz, v.normal, v.vertexID);
                VertexPositionInputs pi = GetVertexPositionInputs(v.vertex.xyz);
                VertexNormalInputs   ni = GetVertexNormalInputs(v.normal);
                o.pos = TransformWorldToHClip(pi.positionWS + ni.normalWS * _OuterOutlineWidth);

                #if _USEOUTLINEDEPTHOFFSET_ON
                    o.pos.z -= _OutlineDepthBias * 0.0001;
                #endif

                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            half4 frag_outline(Vary_OL i) : SV_Target
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

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);
            TEXTURE2D(_ToonRamp); SAMPLER(sampler_ToonRamp);
            float4 _MainTex_ST;
            float4 _Color, _RimColor, _AmbientColor, _InnerLineColor, _OuterOutlineColor, _ShadowColor;
            float  _TextureIntensity, _ShadowStrength;
            float  _LightSensitivity, _RampSmoothing, _DetailBias, _DepthNear, _DepthFar, _ManualDetail;
            float  _RimPower, _InnerLineThreshold, _InnerLineBlur, _InnerLineStrength;
            float  _BumpScale;
            float  _UseDebugDefaults, _EnableAlphaTest, _AlphaCutoff;
            float  _DebugView;
            float  _EnableRim, _EnableOuterOutline, _EnableInnerLines;

            v2f vert(appdata v)
            {
                v2f o;
                OVR_FETCH_POS_NORM(v.vertex.xyz, v.normal, v.vertexID);
                VertexPositionInputs pi = GetVertexPositionInputs(v.vertex.xyz);
                VertexNormalInputs   ni = GetVertexNormalInputs(v.normal, v.tangent);
                o.pos       = pi.positionCS;
                o.uv        = TRANSFORM_TEX(v.uv, _MainTex);
                o.posWS     = pi.positionWS;
                o.nWS       = ni.normalWS;
                o.viewDirWS = GetWorldSpaceViewDir(pi.positionWS);
                o.tWS       = ni.tangentWS;
                o.bWS       = ni.bitangentWS;
                return o;
            }

            half4 frag(v2f IN) : SV_Target
            {
                // Local copies for debug override
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
                if (_EnableAlphaTest > 0.5)
                    clip(texColor.a - _AlphaCutoff);

                half3 baseColor = lerp(_Color.rgb, texColor.rgb * _Color.rgb, textureIntensity);
                half4 albedo    = half4(baseColor, texColor.a * _Color.a);

                // Normal map → world-space normal (GLTFast GLB raw-RGB format)
                half3 normalTS = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, IN.uv).rgb * 2.0h - 1.0h;
                normalTS.xy   *= _BumpScale;
                normalTS        = normalize(normalTS);
                float3x3 TBN   = float3x3(normalize(IN.tWS), normalize(IN.bWS), normalize(IN.nWS));
                float3 nWS     = normalize(mul(normalTS, TBN));

                float3 vWS = normalize(IN.viewDirWS);

                int debugMode = (int)_DebugView;

                // ==================== TEXTURE SOBEL EDGE DETECTION (SIMPLE STEP) ====================
                float sobelEdge = 0.0;
                if (_EnableInnerLines > 0.5)
                {
                    float off   = _InnerLineBlur * 0.001;
                    float3 luma = float3(0.2126, 0.7152, 0.0722);

                    float tl = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-off,  off)).rgb, luma);
                    float t  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(   0,  off)).rgb, luma);
                    float tr = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2( off,  off)).rgb, luma);
                    float l  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-off,    0)).rgb, luma);
                    float r  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2( off,    0)).rgb, luma);
                    float bl = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-off, -off)).rgb, luma);
                    float b  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(   0, -off)).rgb, luma);
                    float br = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2( off, -off)).rgb, luma);

                    float sobelX  = (tr + 2.0*r + br) - (tl + 2.0*l + bl);
                    float sobelY  = (tl + 2.0*t + tr) - (bl + 2.0*b + br);
                    float edgeMag = sqrt(sobelX * sobelX + sobelY * sobelY);

                    sobelEdge = step(_InnerLineThreshold, edgeMag) * _InnerLineStrength;
                }

                if (debugMode == 1) return half4(sobelEdge.xxx, 1.0); // RawSobel

                // ==================== XTOON 2D RAMP SHADING ====================
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
                float3 shaded = lerp(albedo.rgb, shadowedBase, shadowStrength);
                shaded += _AmbientColor.rgb * albedo.rgb;

                if (_EnableRim > 0.5)
                {
                    float rim = pow(1.0 - saturate(dot(vWS, nWS)), rimPower);
                    shaded += rim * _RimColor.rgb;
                }

                shaded = lerp(shaded, _InnerLineColor.rgb, sobelEdge);

                return half4(shaded, albedo.a);
            }
            ENDHLSL
        }

        // ── DepthNormals — writes normal-map-perturbed normals to URP's
        //    _CameraNormalsTexture so screen-space post-process edge shaders see bump detail.
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
    CustomEditor "AvaturnPresetShaderGUI"
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
