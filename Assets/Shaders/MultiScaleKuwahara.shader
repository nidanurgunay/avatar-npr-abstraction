Shader "NPR/MultiScaleKuwahara"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }
        ZWrite Off Cull Off ZTest Always

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        
        struct Attributes
        {
            float4 positionOS : POSITION;
            float2 uv : TEXCOORD0;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD0;
            UNITY_VERTEX_OUTPUT_STEREO
        };

        Varyings Vertex(Attributes input)
        {
            Varyings output;
            UNITY_SETUP_INSTANCE_ID(input);
            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
            output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
            output.uv = input.uv;
            return output;
        }

        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);
        float4 _MainTex_TexelSize;
        
        TEXTURE2D(_StructureTensor);
        SAMPLER(sampler_StructureTensor);
        
        TEXTURE2D(_CoarseTex);
        SAMPLER(sampler_CoarseTex);

        float _KernelSize;
        float _Sharpness;
        float _Hardness;
        float _Alpha;
        
        float _EdgeThresholdMin;
        float _EdgeThresholdMax;
        float4 _BlurDirection;
        
        float Luminance(float3 color)
        {
            return dot(color, float3(0.2126, 0.7152, 0.0722));
        }
        ENDHLSL

        // Pass 0: Structure Tensor (Sobel gradients)
        Pass
        {
            Name "StructureTensor"
            HLSLPROGRAM
            #pragma multi_compile _ STEREO_INSTANCING_ON STEREO_MULTIVIEW_ON UNITY_SINGLE_PASS_STEREO STEREO_CUBEMAP_RENDER_ON
            #pragma vertex Vertex
            #pragma fragment Fragment

            float4 Fragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.uv;
                float3 offset = float3(_MainTex_TexelSize.xy, 0.0);
                
                float tl = Luminance(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-offset.x, -offset.y)).rgb);
                float t  = Luminance(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(0, -offset.y)).rgb);
                float tr = Luminance(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(offset.x, -offset.y)).rgb);
                float l  = Luminance(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-offset.x, 0)).rgb);
                float r  = Luminance(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(offset.x, 0)).rgb);
                float bl = Luminance(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-offset.x, offset.y)).rgb);
                float b  = Luminance(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(0, offset.y)).rgb);
                float br = Luminance(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(offset.x, offset.y)).rgb);
                
                float gx = -tl - 2.0*l - bl + tr + 2.0*r + br;
                float gy = -tl - 2.0*t - tr + bl + 2.0*b + br;
                
                return float4(gx * gx, gx * gy, gy * gy, 1.0);
            }
            ENDHLSL
        }

        // Pass 1: Tensor Blur (Separable)
        Pass
        {
            Name "TensorBlur"
            HLSLPROGRAM
            #pragma multi_compile _ STEREO_INSTANCING_ON STEREO_MULTIVIEW_ON UNITY_SINGLE_PASS_STEREO STEREO_CUBEMAP_RENDER_ON
            #pragma vertex Vertex
            #pragma fragment Fragment

            float4 Fragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.uv;
                float2 offset = _BlurDirection.xy * _MainTex_TexelSize.xy;
                
                float4 sum = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv) * 0.382928;
                sum += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + offset) * 0.241732;
                sum += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv - offset) * 0.241732;
                sum += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + offset * 2.0) * 0.060598;
                sum += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv - offset * 2.0) * 0.060598;
                sum += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + offset * 3.0) * 0.005977;
                sum += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv - offset * 3.0) * 0.005977;
                
                return sum;
            }
            ENDHLSL
        }

        // Pass 2: Anisotropic Kuwahara Filter
        Pass
        {
            Name "KuwaharaFilter"
            HLSLPROGRAM
            #pragma multi_compile _ STEREO_INSTANCING_ON STEREO_MULTIVIEW_ON UNITY_SINGLE_PASS_STEREO STEREO_CUBEMAP_RENDER_ON
            #pragma vertex Vertex
            #pragma fragment Fragment
            #pragma target 4.5

            float4 Fragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.uv;
                float4 tensor = SAMPLE_TEXTURE2D(_StructureTensor, sampler_StructureTensor, uv);
                float E = tensor.x;
                float F = tensor.y;
                float G = tensor.z;
                
                float disc = sqrt(max(0.0, (E-G)*(E-G) + 4.0*F*F));
                float lambda1 = 0.5 * (E + G + disc);
                float lambda2 = 0.5 * (E + G - disc);
                
                float anisotropy = (lambda1 + lambda2) > 0.0 ? (lambda1 - lambda2) / (lambda1 + lambda2) : 0.0;
                float angle = (F == 0.0 && E == G) ? 0.0 : 0.5 * atan2(2.0*F, E-G);
                
                float a = _KernelSize * clamp((_Alpha + anisotropy) / _Alpha, 0.1, 2.0);
                float b = _KernelSize * clamp(_Alpha / (_Alpha + anisotropy), 0.1, 2.0);
                
                float cos_phi = cos(angle);
                float sin_phi = sin(angle);
                
                float2x2 R = float2x2(cos_phi, -sin_phi, sin_phi, cos_phi);
                float2x2 S = float2x2(0.5/a, 0.0, 0.0, 0.5/b);
                float2x2 SR = mul(S, R);
                
                int max_x = (int)(sqrt(a*a * cos_phi*cos_phi + b*b * sin_phi*sin_phi));
                int max_y = (int)(sqrt(a*a * sin_phi*sin_phi + b*b * cos_phi*cos_phi));
                int max_radius = (int)ceil(_KernelSize * 2.0);
                
                float3 means[8];
                float3 stds[8];
                float weights[8];
                
                [unroll]
                for(int i=0; i<8; i++) {
                    means[i] = float3(0,0,0);
                    stds[i] = float3(0,0,0);
                    weights[i] = 0.0;
                }
                
                [loop]
                for (int y = -max_radius; y <= max_radius; y++) {
                    if (abs(y) > max_y) continue;
                    [loop]
                    for (int x = -max_radius; x <= max_radius; x++) {
                        if (abs(x) > max_x) continue;
                        float2 offset = float2(x, y);
                        float2 v = mul(SR, offset);
                        
                        float dSq = dot(v, v);
                        if (dSq <= 0.25) {
                            // Use LOD 0 to prevent illegal mipmap gradient instructions inside dynamic loops
                            float3 c = SAMPLE_TEXTURE2D_LOD(_MainTex, sampler_MainTex, uv + offset * _MainTex_TexelSize.xy, 0).rgb;
                            float phi = atan2(v.y, v.x);
                            
                            [unroll]
                            for(int k=0; k<8; k++) {
                                float dPhi = phi - (k * 3.14159265 / 4.0);
                                if(dPhi > 3.14159265) dPhi -= 2.0 * 3.14159265;
                                if(dPhi < -3.14159265) dPhi += 2.0 * 3.14159265;
                                
                                float wk = exp(-_Hardness * dPhi * dPhi) * exp(-_Hardness * dSq);
                                
                                means[k] += c * wk;
                                stds[k] += c * c * wk;
                                weights[k] += wk;
                            }
                        }
                    }
                }
                
                float4 result = float4(0,0,0,0);
                float totalWeight = 0;
                
                [unroll]
                for (int k = 0; k < 8; k++) {
                    if(weights[k] > 0.0) {
                        float3 mean = means[k] / weights[k];
                        float3 std = stds[k] / weights[k];
                        float variance = abs(Luminance(std) - Luminance(mean)*Luminance(mean));
                        
                        float w = 1.0 / (1.0 + pow(variance * 1000.0, 0.5 * _Sharpness));
                        result.rgb += mean * w;
                        totalWeight += w;
                    }
                }
                
                return float4(result.rgb / totalWeight, 1.0);
            }
            ENDHLSL
        }

        // Pass 3: Multi-Scale Blend
        Pass
        {
            Name "BlendScales"
            HLSLPROGRAM
            #pragma multi_compile _ STEREO_INSTANCING_ON STEREO_MULTIVIEW_ON UNITY_SINGLE_PASS_STEREO STEREO_CUBEMAP_RENDER_ON
            #pragma vertex Vertex
            #pragma fragment Fragment

            float4 Fragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.uv;
                float4 fineColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
                float4 coarseColor = SAMPLE_TEXTURE2D(_CoarseTex, sampler_CoarseTex, uv);
                float4 tensor = SAMPLE_TEXTURE2D(_StructureTensor, sampler_StructureTensor, uv);
                
                // Re-evaluate Edge strength based on the fine structure tensor (Trace is the gradient magnitude squared)
                float E = tensor.x;
                float G = tensor.z;
                float edgeStrength = sqrt(E + G);
                
                // High edge strength approaches 1.0 (lerps toward fineColor).
                // Low edge strength approaches 0.0 (uses coarseColor for broad flat brush strokes)
                float t = smoothstep(_EdgeThresholdMin, _EdgeThresholdMax, edgeStrength);
                
                return lerp(coarseColor, fineColor, t);
            }
            ENDHLSL
        }

        // Pass 4: Masked Composite
        Pass
        {
            Name "MaskedComposite"
            HLSLPROGRAM
            #pragma multi_compile _ STEREO_INSTANCING_ON STEREO_MULTIVIEW_ON UNITY_SINGLE_PASS_STEREO STEREO_CUBEMAP_RENDER_ON
            #pragma vertex Vertex
            #pragma fragment Fragment

            TEXTURE2D(_OriginalScene);
            SAMPLER(sampler_OriginalScene);
            TEXTURE2D(_AvatarMask);
            SAMPLER(sampler_AvatarMask);

            float4 Fragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.uv;
                float4 original = SAMPLE_TEXTURE2D(_OriginalScene, sampler_OriginalScene, uv);
                float4 filtered = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
                float mask = SAMPLE_TEXTURE2D(_AvatarMask, sampler_AvatarMask, uv).r;
                
                return lerp(original, filtered, mask);
            }
            ENDHLSL
        }
    }
}