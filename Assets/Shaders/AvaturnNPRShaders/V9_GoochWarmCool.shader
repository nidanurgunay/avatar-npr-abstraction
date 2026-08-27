// Version 9: Gooch Warm-Cool Shading
// Implements the Gooch (1998) warm-cool tone transfer model for Avaturn.
// Lit surfaces receive a warm hue offset (yellow/orange); shadowed surfaces
// receive a cool hue offset (blue). The blend is continuous along NdotL,
// optionally quantized into toon bands. Inspired by NPR rendering approaches
// documented in VR rehabilitation literature (Springer Virtual Reality, 2024).

Shader "Custom/V9_GoochWarmCool"
{
    Properties
    {
        [Header(Base)]
        _Color ("Main Color", Color) = (1,1,1,1)
        _MainTex ("Texture", 2D) = "white" {}
        _TextureIntensity ("Texture Intensity", Range(0, 1)) = 1.0

        [Space(10)]
        [Header(Gooch Warm Cool Tones)]
        _WarmColor ("Warm Color (lit side)", Color) = (0.85, 0.58, 0.18, 1)
        _CoolColor ("Cool Color (shadow side)", Color) = (0.12, 0.18, 0.62, 1)
        _WarmInfluence ("Warm Surface Mix (alpha)", Range(0, 1)) = 0.45
        _CoolInfluence ("Cool Surface Mix (beta)", Range(0, 1)) = 0.40

        [Space(10)]
        [Header(Toon Quantization)]
        [Toggle] _EnableToon ("Enable Toon Bands", Float) = 0
        _ToonSteps ("Band Count", Range(1, 8)) = 3
        _ToonSmoothness ("Band Edge Smoothness", Range(0.001, 0.1)) = 0.03

        [Space(10)]
        [Header(Outline)]
        _OutlineWidth ("Outline Width (world)", Range(0, 0.5)) = 0.002
        _OutlineColor ("Outline Color", Color) = (0,0,0,1)

        [Space(10)]
        [Header(Rim)]
        [Toggle] _EnableRim ("Enable Rim Lighting", Float) = 1
        _RimColor ("Rim Color", Color) = (1.0, 0.92, 0.78, 1)
        _RimPower ("Rim Power", Range(0.5, 10.0)) = 3.5

        [Space(10)]
        [Header(Alpha)]
        [Toggle] _EnableAlphaTest ("Enable Alpha Test (eyelashes)", Float) = 0
        _AlphaCutoff ("Alpha Cutoff", Range(0, 1)) = 0.07
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        // ─── OUTLINE PASS (inverted hull) ───────────────────────────────────
        Pass
        {
            Name "GoochOutline"
            Cull Front
            ZWrite On
            ZTest Less

            HLSLPROGRAM
            #pragma vertex vert_outline
            #pragma fragment frag_outline
            #pragma target 3.5

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "../CommonNPRShaders/OvrVertexFetchBridge.hlsl"

            struct appdata_o
            {
                float4 vertex    : POSITION;
                float3 normal    : NORMAL;
                float2 uv        : TEXCOORD0;
                uint   vertexID  : SV_VertexID;
            };

            struct v2f_o
            {
                float4 pos : SV_POSITION;
                float2 uv  : TEXCOORD0;
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            float4 _MainTex_ST;
            float  _OutlineWidth;
            float4 _OutlineColor;
            float  _EnableAlphaTest;
            float  _AlphaCutoff;

            v2f_o vert_outline(appdata_o v)
            {
                v2f_o o;
                OVR_FETCH_POS_NORM(v.vertex.xyz, v.normal, v.vertexID);
                VertexPositionInputs pi = GetVertexPositionInputs(v.vertex.xyz);
                VertexNormalInputs   ni = GetVertexNormalInputs(v.normal);
                float3 posWS = pi.positionWS + ni.normalWS * _OutlineWidth;
                o.pos = TransformWorldToHClip(posWS);
                o.uv  = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            half4 frag_outline(v2f_o i) : SV_Target
            {
                if (_EnableAlphaTest > 0.5)
                    clip(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).a - _AlphaCutoff);
                return _OutlineColor;
            }
            ENDHLSL
        }

        // ─── MAIN PASS — Gooch warm-cool ────────────────────────────────────
        Pass
        {
            Name "GoochForwardLit"
            Tags { "LightMode"="UniversalForward" }
            Cull Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.5
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma shader_feature_local _ENABLETOON_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "../CommonNPRShaders/OvrVertexFetchBridge.hlsl"

            struct appdata
            {
                float4 vertex   : POSITION;
                float3 normal   : NORMAL;
                float2 uv       : TEXCOORD0;
                uint   vertexID : SV_VertexID;
            };

            struct v2f
            {
                float4 pos   : SV_POSITION;
                float2 uv    : TEXCOORD0;
                float3 posWS : TEXCOORD1;
                float3 nWS   : TEXCOORD2;
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            float4 _MainTex_ST;
            float4 _Color;
            float  _TextureIntensity;
            float4 _WarmColor;
            float4 _CoolColor;
            float  _WarmInfluence;
            float  _CoolInfluence;
            float  _ToonSteps;
            float  _ToonSmoothness;
            float4 _RimColor;
            float  _RimPower;
            float  _EnableRim;
            float  _EnableAlphaTest;
            float  _AlphaCutoff;

            v2f vert(appdata v)
            {
                v2f o;
                OVR_FETCH_POS_NORM(v.vertex.xyz, v.normal, v.vertexID);
                VertexPositionInputs pi = GetVertexPositionInputs(v.vertex.xyz);
                VertexNormalInputs   ni = GetVertexNormalInputs(v.normal);
                o.pos   = pi.positionCS;
                o.uv    = TRANSFORM_TEX(v.uv, _MainTex);
                o.posWS = pi.positionWS;
                o.nWS   = ni.normalWS;
                return o;
            }

            half4 frag(v2f IN) : SV_Target
            {
                half4 tex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);
                if (_EnableAlphaTest > 0.5)
                    clip(tex.a - _AlphaCutoff);

                half3 baseColor = lerp(_Color.rgb, tex.rgb * _Color.rgb, _TextureIntensity);

                float3 nWS = normalize(IN.nWS);
                float3 vWS = normalize(_WorldSpaceCameraPos - IN.posWS);

                Light  mainLight = GetMainLight();
                float  NdotL     = dot(nWS, mainLight.direction);

                // Gooch blend parameter: maps NdotL from [-1,1] into [0,1].
                // t=0 -> fully shadowed (cool side), t=1 -> fully lit (warm side).
                float t = (NdotL + 1.0) * 0.5;

                // Optional toon quantization applied along the Gooch ramp so the
                // warm-cool gradient snaps into discrete bands rather than smoothly
                // interpolating. This combines the Gooch hue shift with the banded
                // look of cel shading (Lake et al., 2000).
                #if _ENABLETOON_ON
                {
                    float steps  = max(1.0, _ToonSteps);
                    float scaled = t * steps;
                    float band   = floor(scaled);
                    float frac   = scaled - band;
                    float blend  = smoothstep(1.0 - _ToonSmoothness, 1.0, frac);
                    t = saturate((band + blend) / steps);
                }
                #endif

                // Gooch (1998) equation:
                //   k_cool = cool_hue + beta  * k_d   (surface tinted toward cool)
                //   k_warm = warm_hue + alpha * k_d   (surface tinted toward warm)
                //   result = lerp(k_cool, k_warm, t)
                half3 cool = _CoolColor.rgb + _CoolInfluence * baseColor;
                half3 warm = _WarmColor.rgb + _WarmInfluence * baseColor;
                half3 gooch = lerp(cool, warm, t) * mainLight.color;

                if (_EnableRim > 0.5)
                {
                    float rim = pow(1.0 - saturate(dot(vWS, nWS)), _RimPower);
                    gooch += rim * _RimColor.rgb;
                }

                return half4(gooch, tex.a * _Color.a);
            }
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    CustomEditor "AvaturnPresetShaderGUI"
}
