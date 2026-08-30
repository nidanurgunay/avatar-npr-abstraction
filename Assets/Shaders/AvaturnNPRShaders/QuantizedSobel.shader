// V8: Color Quantization + Texture Sobel + Normal-Map Sobel + XToon 2D Ramp
//
// Abstraction pipeline:
//   1. XToon 2D ramp shading (same as VXT / V3-V5) — depth/curvature/manual V-axis
//   2. Quantize lit colour to N discrete steps (posterisation)
//   3. Sobel on the quantized luma  → edges at colour-region boundaries
//   4. Sobel on world-space normal (ddx/ddy on bump-perturbed nWS) → crease/ridge edges
//   5. Both edge signals combined into a single dark line
//
// Lighting: XToon 2D ramp (NdotL × detail axis) — matches V3-V5 and VXT
// Outline:  inverted-hull geometry pass
// DepthNormals: feeds bump-map detail into URP's _CameraNormalsTexture

Shader "Custom/QuantizedSobel"
{
    Properties
    {
        _MainTex         ("Albedo Texture",    2D)          = "white" {}
        _Color           ("Main Color",        Color)       = (1,1,1,1)
        _TextureIntensity("Texture Intensity", Range(0,1))  = 1.0

        [Normal]
        _BumpMap  ("Normal Map",      2D)         = "bump" {}
        _BumpScale("Normal Intensity",Range(0,2)) = 1.0

        [Header(XToon 2D Ramp Shading)]
        _ToonRamp        ("2D Toon Ramp",      2D)           = "white" {}
        _LightSensitivity("Light Sensitivity", Range(0,1))   = 0.8
        _RampSmoothing   ("Ramp Smoothing",    Range(0,0.5)) = 0.05
        _ShadowColor     ("Shadow Color",      Color)        = (0.3,0.3,0.45,1)
        _ShadowStrength  ("Shadow Strength",   Range(0,1))   = 0.7
        [KeywordEnum(Depth, Curvature, Manual)] _DetailMode ("Detail Mode", Float) = 0
        _DetailBias      ("Detail Bias",  Range(0,1))  = 0.5
        _DepthNear       ("Depth Near",   Range(0,20)) = 5.0
        _DepthFar        ("Depth Far",    Range(1,100)) = 50.0
        _ManualDetail    ("Manual Detail",Range(0,1))  = 0.5

        [Header(Color Quantization)]
        _QuantizeSteps("Colour Steps", Range(2,32)) = 8.0

        [Toggle] _EnableRim ("Enable Rim Lighting", Float) = 1
        _RimColor ("Rim Color", Color)         = (0.408,0.408,0.408,1)
        _RimPower ("Rim Power", Range(0.5,10)) = 3.0

        [Header(Outer Outline)]
        _OuterOutlineWidth("Outline Width", Range(0,0.05)) = 0.003
        _OuterOutlineColor("Outline Color", Color)         = (0,0,0,1)

        [Header(Sobel on Quantized Texture)]
        [Toggle] _EnableTexSobel  ("Enable",          Float)          = 1
        _TexEdgeColor             ("Edge Color",       Color)          = (0,0,0,1)
        _TexEdgeThreshold         ("Threshold",        Range(0.001,1)) = 0.1
        _TexEdgeSampleDist        ("Sample Distance",  Range(0.1,10))  = 1.0
        _TexEdgeStrength          ("Strength",         Range(0,1))     = 1.0

        [Header(Skin Color Discard)]
        [Toggle] _EnableSkinDiscard("Discard Skin Edges", Float)    = 0
        _SkinHueMin               ("Skin Hue Min",    Range(0,0.5)) = 0.02
        _SkinHueMax               ("Skin Hue Max",    Range(0,0.5)) = 0.12
        _SkinSatMin               ("Skin Sat Min",    Range(0,1))   = 0.15

        [Header(Normal Edge Detection)]
        [Toggle] _EnableNormSobel ("Enable",          Float)          = 1
        _NormEdgeColor            ("Edge Color",       Color)          = (0,0,0,1)
        _NormEdgeThreshold        ("Threshold",        Range(0,500))   = 20.0
        _NormEdgeSoftness         ("Softness",         Range(0.1,5))   = 1.5
        _NormEdgeStrength         ("Strength",         Range(0,1))     = 1.0

        [Toggle] _EnableAlphaTest("Alpha Test (eyelashes)", Float) = 0
        _AlphaCutoff("Alpha Cutoff", Range(0,1)) = 0.07
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
            #pragma vertex   vert_outline
            #pragma fragment frag_outline
            #pragma target   3.5
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

            Vary_OL vert_outline(Attr_OL v)
            {
                Vary_OL o;
                OVR_FETCH_POS_NORM(v.vertex.xyz, v.normal, v.vertexID);
                VertexPositionInputs pi = GetVertexPositionInputs(v.vertex.xyz);
                VertexNormalInputs   ni = GetVertexNormalInputs(v.normal);
                float3 posWS = pi.positionWS + ni.normalWS * _OuterOutlineWidth;
                o.pos = TransformWorldToHClip(posWS);
                o.uv  = TRANSFORM_TEX(v.uv, _MainTex);
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
                float4 pos        : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 posWS      : TEXCOORD1;
                float3 nWS        : TEXCOORD2;
                float3 tWS        : TEXCOORD3;
                float3 bWS        : TEXCOORD4;
                float4 shadowCoord: TEXCOORD5;
            };

            TEXTURE2D(_MainTex);  SAMPLER(sampler_MainTex);
            TEXTURE2D(_BumpMap);  SAMPLER(sampler_BumpMap);
            TEXTURE2D(_ToonRamp); SAMPLER(sampler_ToonRamp);
            float4 _MainTex_ST;
            float4 _Color;
            float  _TextureIntensity;
            float  _BumpScale;
            float  _LightSensitivity;
            float  _RampSmoothing;
            float4 _ShadowColor;
            float  _ShadowStrength;
            float  _DetailBias;
            float  _DepthNear;
            float  _DepthFar;
            float  _ManualDetail;
            float  _QuantizeSteps;
            float4 _RimColor;
            float  _RimPower;
            float  _EnableRim;
            float  _EnableTexSobel;
            float4 _TexEdgeColor;
            float  _TexEdgeThreshold;
            float  _TexEdgeSampleDist;
            float  _TexEdgeStrength;
            float  _EnableSkinDiscard;
            float  _SkinHueMin;
            float  _SkinHueMax;
            float  _SkinSatMin;
            float  _EnableNormSobel;
            float4 _NormEdgeColor;
            float  _NormEdgeThreshold;
            float  _NormEdgeSoftness;
            float  _NormEdgeStrength;
            float  _EnableAlphaTest;
            float  _AlphaCutoff;

            float3 Quantize(float3 col, float steps)
            {
                return floor(col * steps + 0.5) / steps;
            }

            // Returns (hue 0-1, saturation 0-1, value 0-1)
            float3 RGBtoHSV(float3 c)
            {
                float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
                float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
                float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
                float  d = q.x - min(q.w, q.y);
                float  e = 1.0e-10;
                return float3(abs(q.z + (q.w - q.y) / (6.0*d + e)), d / (q.x + e), q.x);
            }

            Vary vert(Attr v)
            {
                Vary o;
                OVR_FETCH_POS_NORM(v.vertex.xyz, v.normal, v.vertexID);
                VertexPositionInputs pi = GetVertexPositionInputs(v.vertex.xyz);
                VertexNormalInputs   ni = GetVertexNormalInputs(v.normal, v.tangent);
                o.pos         = pi.positionCS;
                o.uv          = TRANSFORM_TEX(v.uv, _MainTex);
                o.posWS       = pi.positionWS;
                o.nWS         = ni.normalWS;
                o.tWS         = ni.tangentWS;
                o.bWS         = ni.bitangentWS;
                o.shadowCoord = GetShadowCoord(pi);
                return o;
            }

            half4 frag(Vary IN) : SV_Target
            {
                half4 texColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);
                if (_EnableAlphaTest > 0.5)
                    clip(texColor.a - _AlphaCutoff);

                // ── Raw base colour (unquantized — lighting will be applied first) ──
                half3  rawBase = lerp(_Color.rgb, texColor.rgb * _Color.rgb, _TextureIntensity);
                half4  albedo  = half4(rawBase, texColor.a * _Color.a);

                // ── Normal map → world-space normal ───────────────────────────
                // GLTFast GLB sub-assets are raw-RGB normal maps — decode as plain RGB.
                half3 nTS    = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, IN.uv).rgb * 2.0h - 1.0h;
                nTS.xy      *= _BumpScale;
                nTS           = normalize(nTS);
                float3x3 TBN = float3x3(normalize(IN.tWS), normalize(IN.bWS), normalize(IN.nWS));
                float3 nWS   = normalize(mul(nTS, TBN));
                float3 vWS   = normalize(_WorldSpaceCameraPos - IN.posWS);

                // ── XToon 2D ramp shading ─────────────────────────────────────
                Light  mainLight = GetMainLight(IN.shadowCoord);
                float  NdotL     = dot(nWS, mainLight.direction) * mainLight.shadowAttenuation;
                float  rampU     = lerp(0.5, saturate(NdotL * 0.5 + 0.5), _LightSensitivity);

                float rampV;
                #if defined(_DETAILMODE_CURVATURE)
                    float3 dNdx     = ddx(nWS);
                    float3 dNdy     = ddy(nWS);
                    float  curv     = length(dNdx) + length(dNdy);
                    rampV = saturate((1.0 - saturate(curv * 10.0)) * (1.0 - _DetailBias) + _DetailBias);
                #elif defined(_DETAILMODE_MANUAL)
                    rampV = saturate(_ManualDetail);
                #else // DEPTH (default)
                    float  depth    = length(_WorldSpaceCameraPos - IN.posWS);
                    rampV = saturate(saturate((depth - _DepthNear) / max(0.001, _DepthFar - _DepthNear)) + _DetailBias);
                #endif

                float3 rampColor    = SAMPLE_TEXTURE2D(_ToonRamp, sampler_ToonRamp, float2(rampU, rampV)).rgb;
                float3 toonBase     = albedo.rgb * rampColor.rgb;
                float  abstractU    = lerp(rampU, 0.5, rampV * 0.6);
                float  dynSmooth    = lerp(_RampSmoothing, _RampSmoothing + 0.35, rampV);
                float  shadowMask   = smoothstep(0.5 - dynSmooth, 0.5 + dynSmooth, abstractU);
                float3 shadowedBase = lerp(toonBase * _ShadowColor.rgb, toonBase, shadowMask);
                float3 litColor     = lerp(albedo.rgb, shadowedBase, _ShadowStrength);

                if (_EnableRim > 0.5)
                {
                    float rim = pow(1.0 - saturate(dot(vWS, nWS)), _RimPower);
                    litColor += rim * _RimColor.rgb;
                }

                // ── Quantize AFTER XToon shading → steps visible in final output
                float3 shaded    = Quantize(litColor, _QuantizeSteps);

                // ── Quantized texture for Sobel edge detection only ───────────
                float3 quantized = Quantize(texColor.rgb, _QuantizeSteps);

                float3 luma = float3(0.299, 0.587, 0.114);

                // ── Sobel on quantized texture ────────────────────────────────
                if (_EnableTexSobel > 0.5)
                {
                    float off = _TexEdgeSampleDist * 0.001;
                    float tl = dot(Quantize(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-off,  off)).rgb, _QuantizeSteps), luma);
                    float t  = dot(Quantize(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(   0,  off)).rgb, _QuantizeSteps), luma);
                    float tr = dot(Quantize(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2( off,  off)).rgb, _QuantizeSteps), luma);
                    float l  = dot(Quantize(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-off,    0)).rgb, _QuantizeSteps), luma);
                    float r  = dot(Quantize(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2( off,    0)).rgb, _QuantizeSteps), luma);
                    float bl = dot(Quantize(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-off, -off)).rgb, _QuantizeSteps), luma);
                    float b  = dot(Quantize(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(   0, -off)).rgb, _QuantizeSteps), luma);
                    float br = dot(Quantize(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2( off, -off)).rgb, _QuantizeSteps), luma);

                    float sobelX  = (tr + 2.0*r + br) - (tl + 2.0*l + bl);
                    float sobelY  = (tl + 2.0*t + tr) - (bl + 2.0*b + br);
                    float edgeMag = sqrt(sobelX*sobelX + sobelY*sobelY);
                    float edge    = step(_TexEdgeThreshold, edgeMag) * _TexEdgeStrength;

                    // Discard edges whose center pixel falls in the skin colour range
                    if (_EnableSkinDiscard > 0.5)
                    {
                        float3 hsv = RGBtoHSV(quantized);
                        bool isSkin = hsv.x >= _SkinHueMin
                                   && hsv.x <= _SkinHueMax
                                   && hsv.y >= _SkinSatMin;
                        if (isSkin) edge = 0.0;
                    }

                    shaded = lerp(shaded, _TexEdgeColor.rgb, edge);
                }

                // ── Normal edge detection (surface curvature, zoom-independent) ──
                // Divides normal derivative by position derivative so both scale
                // equally with zoom — the ratio (curvature) stays constant.
                // nWS already includes BumpMap contribution via TBN.
                if (_EnableNormSobel > 0.5)
                {
                    float3 dNdx    = ddx(nWS);
                    float3 dNdy    = ddy(nWS);
                    float3 dPdx    = ddx(IN.posWS);
                    float3 dPdy    = ddy(IN.posWS);
                    float  curvX   = length(dNdx) / (length(dPdx) + 1e-5);
                    float  curvY   = length(dNdy) / (length(dPdy) + 1e-5);
                    float  edgeMag = sqrt(curvX * curvX + curvY * curvY);
                    float  edge    = smoothstep(_NormEdgeThreshold,
                                               _NormEdgeThreshold * _NormEdgeSoftness,
                                               edgeMag) * _NormEdgeStrength;
                    shaded = lerp(shaded, _NormEdgeColor.rgb, edge);
                }

                return half4(shaded, albedo.a);
            }
            ENDHLSL
        }

        // ── DepthNormals ─────────────────────────────────────────────────────
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

            struct DNAttr { float4 positionOS : POSITION; float3 normalOS : NORMAL; float4 tangentOS : TANGENT; float2 uv : TEXCOORD0; };
            struct DNVary  { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; float3 normalWS : TEXCOORD1; float3 tangentWS : TEXCOORD2; float3 bitangentWS : TEXCOORD3; };

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
                float3x3 TBN = float3x3(normalize(i.tangentWS), normalize(i.bitangentWS), normalize(i.normalWS));
                float3 nWS   = normalize(mul(nTS, TBN));
                return half4(NormalizeNormalPerPixel(nWS), 0.0);
            }
            ENDHLSL
        }
    }
    CustomEditor "AvaturnPresetShaderGUI"
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
