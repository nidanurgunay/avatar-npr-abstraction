// Copy of Meta's Cel-Avatar-Meta.shader with Sobel inner-edge detection added.
//
// The SDK's AppSpecificPostManipulation hook (called at the very end of the
// fragment shader, after all cel lighting is composited) is implemented in
// app_specific/app_functions.hlsl.  It runs a 3x3 Sobel kernel on the normal
// map's XY channels and blends the edge colour into the final output.
//
// Only the URP SubShader (target 3.5) is included - that is what Quest 3 uses.
// Relative includes for app_specific/ resolve from this file's location.
// SDK HLSL files are referenced via absolute Packages/ paths so this shader
// can live anywhere in Assets/ without breaking the include chain.

Shader "Avatar/CelNPRSobel"
{
    Properties
    {
        [Header(Compute Skinning Support)]
        u_AttributeTexture ("Vertex Attribute map", 3D) = "white" {}

        [Header(PBR Textures)]
        [NoScaleOffset] u_BaseColorSampler ("Base Color", 2D) = "white" {}
        u_BaseColorUVSet ("Base Color UV Set", Int) = 0

        [NoScaleOffset] u_MetallicRoughnessSampler ("Metallic Roughness", 2D) = "white" {}

        [NoScaleOffset] u_NormalSampler ("Normal map", 2D) = "bump" {}
        u_NormalUVSet ("Normal UV Set", Int) = 0
        u_NormalScale ("Normal map scale", Range(0, 2)) = 1.0

        u_Exposure ("Material Exposure", Range(0, 2)) = 1.0

        [Space]
        [Header(SSS Curvature)]
        u_SSSCurvatureScaleBias ("SSS Curvature Scale Bias", Vector) = (12.84, 0.0186, 0.0)

        [Space]
        [Header(Variants)]
        [KeywordEnum(2 Light, 2 Standard, 2 Experimental, 1 Light, 1 Standard)] Style ("Style", Float) = -1

        [Enum(UnityEngine.Rendering.CullMode)] _CullFront ("Cull", Float) = 1
        [Enum(UnityEngine.Rendering.CullMode)] _CullBack  ("Cull", Float) = 2

        [Space]
        [Header(Additional parameters)]
        u_HairSubsurfaceColor ("Hair Sub-Surface Color", Color) = (1,1,1,1)
        u_HairSpecularColorFactor ("Hair Specular Color Factor", Color) = (1,1,1,1)
        u_HairSpecularShiftIntensity ("Hair Specular Shift Intensity", Range(-1,1)) = 0.2
        u_HairSpecularWhiteIntensity ("Hair Specular White Intensity", Range(0,10)) = 0.2
        u_HairSpecularColorIntensity ("Hair Specular Color Intensity", Range(0,10)) = 0.2
        u_HairSpecularColorOffset ("Hair Specular Color Offset", Range(-1,1)) = 0.2
        u_HairRoughness ("Hair Roughness", Range(0,1)) = 0.2
        u_HairColorRoughness ("Hair Color Roughness", Range(0,1)) = 0.4
        u_HairAnisotropicIntensity ("Hair Anistropic Intensity", Range(-1,1)) = 0.5
        u_HairSpecularNormalIntensity ("Hair Specular Normal Intensity", Range(0,1)) = 1.0
        u_HairDiffusedIntensity ("Hair Diffuse Intensity", Range(0,10)) = 0.25

        u_FacialHairSubsurfaceColor ("Facial Hair Sub-Surface Color", Color) = (1,1,1,1)
        u_FacialHairSpecularColorFactor ("Facial Hair Specular Color Factor", Color) = (1,1,1,1)
        u_FacialHairSpecularShiftIntensity ("Facial Hair Specular Shift Intensity", Range(-1,1)) = 0.2
        u_FacialHairSpecularWhiteIntensity ("Facial Hair Specular White Intensity", Range(0,10)) = 0.2
        u_FacialHairSpecularColorIntensity ("Facial Hair Specular Color Intensity", Range(0,10)) = 0.2
        u_FacialHairSpecularColorOffset ("Facial Hair Specular Color Offset", Range(-1,1)) = 0.2
        u_FacialHairRoughness ("Facial Hair Roughness", Range(0,1)) = 0.2
        u_FacialHairColorRoughness ("Facial Hair Color Roughness", Range(0,1)) = 0.4
        u_FacialHairAnisotropicIntensity ("Facial Hair Anistropic Intensity", Range(-1,1)) = 0.5
        u_FacialHairSpecularNormalIntensity ("Facial Hair Specular Normal Intensity", Range(0,1)) = 1.0
        u_FacialHairDiffusedIntensity ("Facial Hair Diffuse Intensity", Range(0,10)) = 0.25

        u_RimLightIntensity ("Rim Light Intensity", Range(0,1)) = 0.0
        u_RimLightBias ("Rim Light Bias", Range(0,1)) = 0.5
        u_RimLightColor ("Rim Light Color", Color) = (1,1,1)
        u_RimLightTransition ("Rim Light Transition", Range(0,0.2)) = 0.2
        u_RimLightStartPosition ("Rim Light Start Position", Range(0,1)) = 0.5
        u_RimLightEndPosition ("Rim Light End Position", Range(0,1)) = 0.5

        u_EyeGlintLightColor ("EyeGlintLightColor", Color) = (1,1,1)

        u_EmissiveColor ("EmissiveColor", Color) = (0,0,0)
        [Toggle] u_EmissiveUseBaseColor ("EmissiveUseBaseColor", Int) = 0
        u_EmissivePulseFrequency ("EmissivePulseFrequency", Range(0,5)) = 0.0

        [Space]
        [Header(Inner Screen Space Edges)]
        _EnableNPREdges ("Enable NPR Edges (use script keyword)", Float) = 1
        _InnerLineColor    ("Inner Line Color",   Color)         = (0,0,0,1)
        _EdgeThreshold     ("Edge Threshold",     Range(0, 0.5)) = 0.05
        _EdgeMax           ("Edge Max",           Range(0.05,2)) = 0.5
        _ColorEdgeWeight   ("Color Edge Weight",  Range(0, 1))   = 0.5
        _InnerLineStrength ("Line Strength",      Range(0, 1))   = 1.0
    }

    // -- URP SubShader (target 3.5 - Quest 3 / Android Vulkan) ----------------
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque" }

        // -- Pass 0: Outline (inverted hull, Cull Front) -----------------------
        Pass
        {
            Tags { "LightMode" = "UniversalForward" }
            Cull Front

            HLSLPROGRAM
            #pragma editor_sync_compilation
            #pragma vertex Vertex_main_instancing
            #pragma fragment Fragment_main
            #pragma target 3.5
            #pragma shader_feature UNITY_PIPELINE_URP
            #define UNITY_PIPELINE_URP
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include_with_pragmas "Packages/com.meta.xr.sdk.avatars/Scripts/Common/Shaders/Recommended/OutlineAvatarMeta.hlsl"
            ENDHLSL
        }

        // -- Pass 1: Forward Lit with Sobel edges (Cull Back) -----------------
        Pass
        {
            Tags { "LightMode" = "UniversalForward" }
            Cull Back

            HLSLPROGRAM
            #pragma editor_sync_compilation
            #pragma vertex Vertex_main_instancing
            #pragma fragment Fragment_main
            #pragma target 3.5
            #pragma multi_compile __ ENABLE_NPR_EDGES
            #pragma shader_feature UNITY_PIPELINE_URP
            #define UNITY_PIPELINE_URP
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            // Our variants and declarations first — in scope when SDK reads them.
            #include_with_pragmas "app_specific/app_variants.hlsl"
            #include "app_specific/app_declarations.hlsl"
            // Main SDK cel shader (declares AppSpecific forward declarations + calls them).
            #include_with_pragmas "Packages/com.meta.xr.sdk.avatars/Scripts/Common/Shaders/Recommended/Style2MetaAvatarCel.hlsl"
            // Our hook definitions — AppSpecificPostManipulation injects edges here.
            // Must be #include_with_pragmas so the ENABLE_NPR_EDGES multi_compile
            // declared inside app_functions.hlsl is picked up by the compiler.
            #include_with_pragmas "app_specific/app_functions.hlsl"
            ENDHLSL
        }

        // -- Pass 2: Motion Vectors ---------------------------------------------
        Pass
        {
            Name "MotionVectors"
            Tags { "LightMode" = "MotionVectors" "RenderType" = "Opaque" }

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex OvrMotionVectorsVertProgram
            #pragma fragment OvrMotionVectorsFragProgram
            #include "Packages/com.meta.xr.sdk.avatars/Scripts/ShaderUtils/OvrAvatarMotionVectorsCore.hlsl"
            ENDHLSL
        }

        // -- Pass 3: XR Motion Vectors ------------------------------------------
        Pass
        {
            Name "XRMotionVectors"
            Tags { "LightMode" = "XRMotionVectors" }
            ColorMask RGBA

            Stencil
            {
                WriteMask 1
                Ref 1
                Comp Always
                Pass Replace
            }

            HLSLPROGRAM
            #define APPLICATION_SPACE_WARP_MOTION 1
            #pragma target 3.5
            #pragma vertex OvrMotionVectorsVertProgram
            #pragma fragment OvrMotionVectorsFragProgram
            #include "Packages/com.meta.xr.sdk.avatars/Scripts/ShaderUtils/OvrAvatarMotionVectorsCore.hlsl"
            ENDHLSL
        }
    }
}
