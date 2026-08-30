// Inverted-hull outline + URP Lit-equivalent surface.
// Pass 0 — Outline : Cull Front, expands vertices along normals, flat outline colour.
// Pass 1 — Surface : UniversalFragmentPBR with standard UnpackNormalScale decode.

Shader "Custom/InvertedHullOutline"
{
    Properties
    {
        [Header(Surface)]
        [MainTexture] _MainTex  ("Albedo", 2D)        = "white" {}
        [MainColor]   _Color    ("Color Tint", Color) = (1, 1, 1, 1)

        [Header(Normal Map)]
        [Normal] _BumpMap  ("Normal Map", 2D) = "bump" {}
        _BumpScale         ("Normal Scale", Float) = 1.0
        [Toggle(_RAW_NORMAL_MAP)] _UseRawNormalMap ("Raw RGB Normal (GLTFast/GLB)", Float) = 0

        [Header(Metallic Smoothness)]
        _Metallic    ("Metallic",   Range(0, 1)) = 0.0
        _Smoothness  ("Smoothness", Range(0, 1)) = 0.5

        [Header(Outline)]
        _OutlineWidth  ("Outline Width (world units)", Range(0, 0.05)) = 0.003
        _OutlineColor  ("Outline Color", Color) = (0, 0, 0, 1)

        [Header(Alpha)]
        [Toggle] _EnableAlphaTest ("Alpha Test (hair / eyelash)", Float) = 0
        _AlphaCutoff  ("Alpha Cutoff", Range(0, 1)) = 0.07
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        // ── Pass 0: Inverted Hull Outline ──────────────────────────────────────
        Pass
        {
            Name "Outline"
            Tags { "LightMode" = "SRPDefaultUnlit" }

            Cull  Front
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag
            #pragma target   3.5

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                half4  _Color;
                half4  _OutlineColor;
                half   _BumpScale;
                half   _Metallic;
                half   _Smoothness;
                float  _OutlineWidth;
                float  _EnableAlphaTest;
                float  _AlphaCutoff;
            CBUFFER_END

            struct Attributes {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };
            struct Varyings {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                float3 posWS    = TransformObjectToWorld(IN.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(IN.normalOS);
                posWS          += normalWS * _OutlineWidth;
                OUT.positionCS  = TransformWorldToHClip(posWS);
                OUT.uv          = TRANSFORM_TEX(IN.uv, _MainTex);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                if (_EnableAlphaTest > 0.5)
                    clip(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv).a - _AlphaCutoff);
                return _OutlineColor;
            }
            ENDHLSL
        }

        // ── Pass 1: URP Lit-equivalent surface ────────────────────────────────
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            Cull  Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag
            #pragma target   3.5

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ EVALUATE_SH_MIXED EVALUATE_SH_VERTEX
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local _RAW_NORMAL_MAP

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                half4  _Color;
                half4  _OutlineColor;
                half   _BumpScale;
                half   _Metallic;
                half   _Smoothness;
                float  _OutlineWidth;
                float  _EnableAlphaTest;
                float  _AlphaCutoff;
            CBUFFER_END

            struct Attributes {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
                float2 lightmapUV : TEXCOORD1;
            };
            struct Varyings {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS   : TEXCOORD2;
                float4 tangentWS  : TEXCOORD3;
                DECLARE_LIGHTMAP_OR_SH(lightmapUV, vertexSH, 4);
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs posInputs  = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs   normInputs = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);
                OUT.positionCS = posInputs.positionCS;
                OUT.positionWS = posInputs.positionWS;
                OUT.uv         = TRANSFORM_TEX(IN.uv, _MainTex);
                OUT.normalWS   = normInputs.normalWS;
                OUT.tangentWS  = half4(normInputs.tangentWS,
                                       IN.tangentOS.w * GetOddNegativeScale());
                OUTPUT_LIGHTMAP_UV(IN.lightmapUV, unity_LightmapST, OUT.lightmapUV);
                OUTPUT_SH(OUT.normalWS, OUT.vertexSH);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv) * _Color;
                if (_EnableAlphaTest > 0.5) clip(albedo.a - _AlphaCutoff);

                half4  bumpSample  = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, IN.uv);
                #if defined(_RAW_NORMAL_MAP)
                // GLTFast GLB: textures are raw RGB, not DXT5nm-encoded.
                half3  normalTS    = normalize(bumpSample.rgb * 2.0h - 1.0h);
                normalTS.xy       *= _BumpScale;
                #else
                // Standard Unity import (PNG as Normal Map = DXT5nm encoded).
                half3  normalTS    = UnpackNormalScale(bumpSample, _BumpScale);
                #endif
                float3 bitangentWS = IN.tangentWS.w * cross(IN.normalWS, IN.tangentWS.xyz);
                float3 normalWS    = normalize(
                    normalTS.x * IN.tangentWS.xyz +
                    normalTS.y * bitangentWS +
                    normalTS.z * IN.normalWS);

                SurfaceData surface = (SurfaceData)0;
                surface.albedo     = albedo.rgb;
                surface.alpha      = albedo.a;
                surface.metallic   = _Metallic;
                surface.smoothness = _Smoothness;
                surface.normalTS   = normalTS;
                surface.occlusion  = 1;

                InputData inputData = (InputData)0;
                inputData.positionWS              = IN.positionWS;
                inputData.normalWS                = normalWS;
                inputData.viewDirectionWS         = GetWorldSpaceNormalizeViewDir(IN.positionWS);
                inputData.shadowCoord             = TransformWorldToShadowCoord(IN.positionWS);
                inputData.fogCoord                = 0;
                inputData.vertexLighting          = 0;
                inputData.bakedGI                 = SAMPLE_GI(IN.lightmapUV, IN.vertexSH, normalWS);
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.positionCS);
                inputData.shadowMask              = SAMPLE_SHADOWMASK(IN.lightmapUV);

                return UniversalFragmentPBR(inputData, surface);
            }
            ENDHLSL
        }

        // ── Pass 2: DepthNormals — gives SSAO correct normals so occlusion
        //           matches the original URP/Lit avatar (no pass = no AO = looks brighter).
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }

            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag
            #pragma target   3.5
            #pragma shader_feature_local _RAW_NORMAL_MAP

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ShaderVariablesFunctions.hlsl"

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                half4  _Color;
                half4  _OutlineColor;
                half   _BumpScale;
                half   _Metallic;
                half   _Smoothness;
                float  _OutlineWidth;
                float  _EnableAlphaTest;
                float  _AlphaCutoff;
            CBUFFER_END

            struct Attributes {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
            };
            struct Varyings {
                float4 positionCS : SV_POSITION;
                float3 normalWS   : TEXCOORD0;
                float4 tangentWS  : TEXCOORD1;
                float2 uv         : TEXCOORD2;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                VertexNormalInputs n = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.normalWS   = n.normalWS;
                OUT.tangentWS  = half4(n.tangentWS, IN.tangentOS.w * GetOddNegativeScale());
                OUT.uv         = TRANSFORM_TEX(IN.uv, _MainTex);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                if (_EnableAlphaTest > 0.5)
                    clip(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv).a - _AlphaCutoff);

                half4 bumpSample = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, IN.uv);
                #if defined(_RAW_NORMAL_MAP)
                half3 normalTS   = normalize(bumpSample.rgb * 2.0h - 1.0h);
                normalTS.xy     *= _BumpScale;
                #else
                half3 normalTS   = UnpackNormalScale(bumpSample, _BumpScale);
                #endif
                float3 bitangentWS = IN.tangentWS.w * cross(IN.normalWS, IN.tangentWS.xyz);
                float3 normalWS    = normalize(
                    normalTS.x * IN.tangentWS.xyz +
                    normalTS.y * bitangentWS +
                    normalTS.z * IN.normalWS);

                return half4(NormalizeNormalPerPixel(normalWS), 0);
            }
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    CustomEditor "InvertedHullPresetShaderGUI"
}
