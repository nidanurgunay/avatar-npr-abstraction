Shader "Avatar/MetaNPR"
{
    Properties
    {
        [Header(Compute Skinning Support)]
        // NOTE: This texture can be visualized in the Unity editor, just expand in inspector and manually change "Dimension" to "2D" on top line
        u_AttributeTexture("Vertex Attribute map", 3D) = "white" {}

        [Header(PBR Textures)]

        [NoScaleOffset] u_BaseColorSampler("Base Color", 2D) = "white" {}
        u_BaseColorUVSet("Base Color UV Set", Int) = 0

        [NoScaleOffset]  u_MetallicRoughnessSampler("Metallic Roughness", 2D) = "white" {}

        [NoScaleOffset] u_NormalSampler("Normal map", 2D) = "bump" {}
        u_NormalUVSet("Normal UV Set", Int) = 0
        u_NormalScale("Normal map scale", Range(0, 2)) = 1.0

        u_Exposure("Material Exposure", Range(0, 2)) = 1.0

        [Space]
        [Header(SSS Curvature)]
        [ShowIfKeyword(SKIN_ON)]
        u_SSSCurvatureScaleBias("SSS Curvature Scale Bias", Vector) = (12.84, 0.0186, 0.0)

        [Space]
        [Header(Variants)]

        [KeywordEnum(2 Light, 2 Standard, 2 Experimental, 1 Light, 1 Standard)] Style("Style", Float) = -1
        // The following proxies only serve to visualize the features for the style above. Real assignment happens in app_variants.hlsl.
        [KeywordProxy(EYE_GLINTS_ON, STYLE_1_LIGHT, STYLE_1_STANDARD, STYLE_2_LIGHT, STYLE_2_STANDARD, STYLE_2_EXPERIMENTAL)] EyeGlints("Eye Glints", Float) = 1
        [KeywordProxy(SKIN_ON, STYLE_1_LIGHT, STYLE_1_STANDARD, STYLE_2_LIGHT, STYLE_2_STANDARD, STYLE_2_EXPERIMENTAL)] Skin("Skin", Float) = 1
        [KeywordProxy(HAS_NORMAL_MAP_ON, STYLE_1_STANDARD, STYLE_2_LIGHT, STYLE_2_STANDARD, STYLE_2_EXPERIMENTAL)] HasNormalMap("Normal Map", Float) = 1
        [KeywordProxy(ENABLE_HAIR_ON, STYLE_1_STANDARD, STYLE_2_STANDARD, STYLE_2_EXPERIMENTAL)] EnableHair("Hair", Float) = 1
        [KeywordProxy(ENABLE_RIM_LIGHT_ON, STYLE_2_STANDARD, STYLE_2_EXPERIMENTAL)] EnableRimLight("Rim Light", Float) = 1
        [KeywordProxy(SIMPLE_OCCLUSION, STYLE_2_LIGHT)] SimpleOcclusion("Simplified Occlusion Model", Float) = 1

        // DEBUG_MODES: Uncomment to use Debug modes, do not create a multi_compile for this, as it takes up permutations and memory. Instead static branch on DEBUG_NONE and the value of floating point uniform "Debug".
        [KeywordEnumWithToggle(DEBUG_MODE_ON, None, BaseColorSRGB, BaseColorLinear, Alpha, Occlusion, Metallic, Roughness, Thickness, Normal, NormalGeometry, NormalWorld, Tangent, Bitangent, F0, EmissiveSrgb, EmissiveLinear, SpecularSrgb, DiffuseSrgb, ClearcoatSrgb, SheenSrgb, TransmissionSrgb, Ambient, AmbientDiffuse, AmbientSpecular, IBLBrdf, Punctual, PunctualDiffuse, PunctualSpecular, Anisotropy, AnisotropyDirection, AnisotropyTangent, AnisotropyBitangent, View, SubsurfaceScattering, AmbientOcclusion, SSSCurvature, SSSCurvaturePunctual, SSSCurvatureAmbient, TexCoord0, TexCoord1, SHIrradiance, Submeshes, MaterialType, Shadows)] Debug("Debug Render", Float) = 0

        // MATERIAL_MODES: Uncomment to use Material modes, must match the multi_compile defined below
        [KeywordEnum(Texture, Vertex)] Material_Mode("Material Mode", Float) = 0

        // Cull mode (Off, Front, Back)
        [Enum(UnityEngine.Rendering.CullMode)] _Cull("Cull", Float) = 2

        [Header(Submesh control)]
        _SubMeshIdCount("Total number of sub-meshes found", Int) = 0
        _IdSlotsPerSubmesh("Maximum number of extensions per material", Int) = 1

        [Space]
        [Header(Additional parameters)]

        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_HairSubsurfaceColor("Hair Sub-Surface Color", Color) = (1, 1, 1, 1)
        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_HairSpecularColorFactor("Hair Specular Color Factor", Color) = (1, 1, 1, 1)
        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_HairSpecularShiftIntensity("Hair Specular Shift Intensity", Range(-1,1)) = .2
        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_HairSpecularWhiteIntensity("Hair Specular White Intensity", Range(0,10)) = .2
        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_HairSpecularColorIntensity("Hair Specular Color Intensity", Range(0,10)) = .2
        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_HairSpecularColorOffset("Hair Specular Color Offset", Range(-1,1)) = .2
        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_HairRoughness("Hair Roughness", Range(0,1)) = .2
        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_HairColorRoughness("Hair Color Roughness", Range(0,1)) = .4
        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_HairAnisotropicIntensity("Hair Anistropic Intensity", Range(-1,1)) = .5
        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_HairSpecularNormalIntensity("Hair Specular Normal Intensity", Range(0,1)) = 1.
        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_HairDiffusedIntensity("Hair Diffuse Intensity", Range(0,10)) = .25

        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_FacialHairSubsurfaceColor("Facial Hair Sub-Surface Color", Color) = (1, 1, 1, 1)
        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_FacialHairSpecularColorFactor("Facial Hair Specular Color Factor", Color) = (1, 1, 1, 1)
        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_FacialHairSpecularShiftIntensity("Facial Hair Specular Shift Intensity", Range(-1,1)) = .2
        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_FacialHairSpecularWhiteIntensity("Facial Hair Specular White Intensity", Range(0,10)) = .2
        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_FacialHairSpecularColorIntensity("Facial Hair Specular Color Intensity", Range(0,10)) = .2
        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_FacialHairSpecularColorOffset("Facial Hair Specular Color Offset", Range(-1,1)) = .2
        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_FacialHairRoughness("Facial Hair Roughness", Range(0,1)) = .2
        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_FacialHairColorRoughness("Facial Hair Color Roughness", Range(0,1)) = .4
        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_FacialHairAnisotropicIntensity("Facial Hair Anistropic Intensity", Range(-1,1)) = .5
        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_FacialHairSpecularNormalIntensity("Facial Hair Specular Normal Intensity", Range(0,1)) = 1.
        [ShowIfKeyword(ENABLE_HAIR_ON)]
        u_FacialHairDiffusedIntensity("Facial Hair Diffuse Intensity", Range(0,10)) = .25

        [ShowIfKeyword(ENABLE_RIM_LIGHT_ON)]
        u_RimLightIntensity("Rim Light Intensity", Range(0,1)) = 0.0
        [ShowIfKeyword(ENABLE_RIM_LIGHT_ON)]
        u_RimLightBias("Rim Light Bias", Range(0.0,1.0)) = 0.5
        [ShowIfKeyword(ENABLE_RIM_LIGHT_ON)]
        u_RimLightColor("Rim Light Color", Color) = (1,1,1)
        [ShowIfKeyword(ENABLE_RIM_LIGHT_ON)]
        u_RimLightTransition("Rim Light Transition", Range(0,0.2)) = 0.2
        [ShowIfKeyword(ENABLE_RIM_LIGHT_ON)]
        u_RimLightStartPosition("Rim Light Start Position", Range(0,1)) = 0.5
        [ShowIfKeyword(ENABLE_RIM_LIGHT_ON)]
        u_RimLightEndPosition("Rim Light End Position", Range(0,1)) = 0.5

        [ShowIfKeyword(EYE_GLINTS_ON)]
        u_EyeGlintLightColor("EyeGlintLightColor", Color) = (1, 1, 1)

        u_EmissiveColor("EmissiveColor", Color) = (0, 0, 0)
        [Toggle] u_EmissiveUseBaseColor("EmissiveUseBaseColor", Int) = 0
        u_EmissivePulseFrequency("EmissivePulseFrequency", Range(0.0, 5)) = 0.0

        // These should not exist here, since they should be in global shader scope and handeled by an external manager:
        //
        //u_DiffuseEnvSampler("IBL Diffuse Cubemap Texture", Cube) = "white" {}
        //u_MipCount("IBL Diffuse Texture Mip Count", Int) = 10
        //u_SpecularEnvSampler ("IBL Specular Cubemap Texture", Cube) = "white" {}
        //u_brdfLUT ("BRDF LUT Texture", 2D) = "Assets/Oculus/Avatar2/Example/Scenes/BRDF_LUT" {}

        [Space]
        [Header(NPR Edge  shared)]
        _InnerLineColor    ("Inner Line Color",   Color)         = (0,0,0,1)

        [Header(NPR Edge  Derivative technique)]
        _ToonBands       ("Toon Bands",       Range(2, 8))   = 4.0
        _ToonStrength    ("Toon Strength",    Range(0, 1))   = 0.0
        _ColorThreshold  ("Color Threshold",  Range(0, 0.5)) = 0.05
        _ColorEdgeMax    ("Color Edge Max",   Range(0.05, 2)) = 0.5
        _ColorStrength   ("Color Strength",   Range(0, 1))   = 1.0
        _NormalThreshold ("Normal Threshold", Range(0, 0.5)) = 0.05
        _NormalEdgeMax   ("Normal Edge Max",  Range(0.05, 2)) = 0.5
        _NormalStrength  ("Normal Strength",  Range(0, 1))   = 1.0

        [Header(NPR Edge  Sobel technique)]
        [Toggle] _EnableSobel ("Enable Sobel", Float) = 1
        _SobelSampleDist ("Sample Distance", Range(0, 10))  = 0.5
        _SobelThreshold  ("Threshold",       Range(0, 1))   = 0.2
        _SobelMax        ("Sobel Max",       Range(0.1, 8)) = 2.0
        _SobelSeamLimit  ("Seam Limit",      Range(0, 1))   = 0.6
        _SobelStrength   ("Strength",        Range(0, 1))   = 1.0

        [Header(NPR Edge  Normal and Fresnel technique)]
        _NormalEdgeThreshold  ("Normal Threshold",   Range(0, 1))    = 0.3
        _NormalEdgeStrength   ("Normal Strength",    Range(0, 1))    = 0.8
        _NormalEdgeSmoothness ("Normal Smoothness",  Range(0.01, 0.5)) = 0.1
        _FresnelEdgeThreshold ("Fresnel Threshold",  Range(0, 1))    = 0.3
        _FresnelEdgeStrength  ("Fresnel Strength",   Range(0, 1))    = 0.5

        [Header(NPR Edge  Gaussian Sobel technique)]
        [Toggle] _GSobelEnableGaussBlur ("Enable Gaussian Blur", Float) = 1
        _GSobelSampleDist     ("Sample Distance",   Range(0, 10))    = 0.5
        _GSobelBlurRadius     ("Blur Radius",       Range(0, 5))     = 0.4
        _GSobelCenterWeight   ("Center Weight",     Range(0.1, 0.5)) = 0.25
        _GSobelCardinalWeight ("Cardinal Weight",   Range(0, 0.3))   = 0.125
        _GSobelDiagonalWeight ("Diagonal Weight",   Range(0, 0.1))   = 0.0625
        _GSobelThreshold      ("Threshold",         Range(0, 0.5))   = 0.2
        _GSobelThreshMin      ("Threshold Min Mult",Range(0, 1))     = 0.2
        _GSobelThreshMax      ("Threshold Max Mult",Range(1, 5))     = 2.0
        _GSobelTightness      ("Tightness",         Range(0, 1))     = 0.2
        _GSobelPowerCurve     ("Power Curve",       Range(0.5, 5))   = 1.5
        _GSobelStrength       ("Strength",          Range(0, 1))     = 1.0
        _GSobelEdgeColor      ("Edge Color",        Color)           = (0,0,0,1)

        [Header(NPR Edge  Hierarchical technique)]
        _HDepthThreshold   ("Depth Threshold",   Range(0.001, 0.2)) = 0.02
        _HNormalThreshold  ("Normal Threshold",  Range(0.05, 1.0))  = 0.3
        _HColorThreshold   ("Colour Threshold",  Range(0.01, 0.5))  = 0.1
        [Toggle] _HEnableGaussBlur ("Gauss Blur", Float)            = 0
        _HBlurRadius       ("Blur Radius",       Range(0, 5))       = 1.0
        _HCenterWeight     ("Center Weight",     Range(0.1, 0.5))   = 0.25
        _HCardinalWeight   ("Cardinal Weight",   Range(0, 0.3))     = 0.125
        _HDiagonalWeight   ("Diagonal Weight",   Range(0, 0.1))     = 0.0625
        _HDepthWeight      ("Depth Weight",      Range(0, 1))       = 0.8
        _HNormalWeight     ("Normal Weight",     Range(0, 1))       = 0.8
        _HColorWeight      ("Colour Weight",     Range(0, 1))       = 0.6
        _HEdgeWidth        ("Edge Width",        Range(0.5, 10))    = 1.5
        _HAdaptiveStrength ("Adaptive Strength", Range(0, 1))       = 0.5
        _HEdgeColor              ("Edge Color",        Color)             = (0,0,0,1)
        [Toggle] _HEnableSkinDiscard ("Skin Colour Discard", Float)       = 0
        _HSkinHueMin             ("Skin Hue Min",     Range(0, 0.2))      = 0.02
        _HSkinHueMax             ("Skin Hue Max",     Range(0, 0.2))      = 0.12
        _HSkinSatMin             ("Skin Sat Min",     Range(0, 1))        = 0.15

        [Header(NPR Effect  Kuwahara technique)]
        _K2Radius    ("Radius",     Range(0.5, 20))  = 2.0
        _K2Strength  ("Strength",   Range(0, 1))     = 1.0
        _K2Alpha     ("Alpha",      Range(0.5, 3))   = 1.0
        _K2Q         ("Q Sharpness",Range(1, 16))    = 8.0
        _K2Tau       ("Tau Floor",  Range(0.001, 0.1)) = 0.02

        [Header(NPR Effect  Kuwahara Sobel technique)]
        _K2SKuwRadius    ("Kuw Radius",    Range(0.5, 20))    = 2.0
        _K2SKuwStrength  ("Kuw Strength",  Range(0, 1))       = 0.8
        _K2SKuwAlpha     ("Kuw Alpha",     Range(0.5, 3))     = 1.0
        _K2SKuwQ         ("Kuw Q",         Range(1, 16))      = 8.0
        _K2SKuwTau       ("Kuw Tau",       Range(0.001, 0.1)) = 0.02
        [Toggle] _K2SEnableGaussBlur ("Enable Gaussian Blur", Float) = 1
        _K2SSobelSampleDist  ("Sobel Sample Dist", Range(0, 10))    = 1.0
        _K2SBlurRadius       ("Blur Radius",       Range(0, 5))     = 1.0
        _K2SCenterWeight     ("Center Weight",      Range(0.1, 0.5)) = 0.25
        _K2SCardinalWeight   ("Cardinal Weight",    Range(0, 0.3))   = 0.125
        _K2SDiagonalWeight   ("Diagonal Weight",    Range(0, 0.1))   = 0.0625
        _K2SThreshold        ("Edge Threshold",     Range(0, 0.5))   = 0.15
        _K2SThreshMin        ("Thresh Min Mult",    Range(0, 1))     = 0.5
        _K2SThreshMax        ("Thresh Max Mult",    Range(1, 5))     = 1.5
        _K2STightness        ("Tightness",          Range(0, 1))     = 0.2
        _K2SPowerCurve       ("Power Curve",        Range(0.5, 5))   = 1.5
        _K2SSobelStrength        ("Edge Strength",    Range(0, 1))       = 1.0

        [Header(NPR Effect  Kuwahara Hierarchical technique)]
        _K2HKuwRadius    ("Kuw Radius",      Range(0.5, 20))    = 2.0
        _K2HKuwStrength  ("Kuw Strength",    Range(0, 1))       = 0.8
        _K2HKuwAlpha     ("Kuw Alpha",       Range(0.5, 3))     = 1.0
        _K2HKuwQ         ("Kuw Q",           Range(1, 16))      = 8.0
        _K2HKuwTau       ("Kuw Tau",         Range(0.001, 0.1)) = 0.02
        _K2HDepthThreshold   ("Depth Threshold",   Range(0.001, 0.2)) = 0.02
        _K2HNormalThreshold  ("Normal Threshold",  Range(0.05, 1))    = 0.3
        _K2HColorThreshold   ("Color Threshold",   Range(0.01, 0.5))  = 0.1
        _K2HDepthWeight      ("Depth Weight",      Range(0, 1))       = 0.8
        _K2HNormalWeight     ("Normal Weight",      Range(0, 1))       = 0.8
        _K2HColorWeight      ("Color Weight",       Range(0, 1))       = 0.6
        _K2HEdgeWidth        ("Edge Width",         Range(0.5, 10))    = 1.5
        _K2HAdaptiveStrength ("Adaptive Strength",  Range(0, 1))       = 0.5
        _K2HHierTightness    ("Hier Tightness",     Range(0, 1))       = 0.5
        _K2HHStrength        ("Hier Edge Strength", Range(0, 1))       = 1.0
        [Toggle] _K2HEnableGaussBlur ("Color Blur", Float)             = 0
        _K2HBlurRadius       ("Color Blur Radius",  Range(0, 5))       = 1.0
        _K2HCenterWeight     ("Center Weight",      Range(0.1, 0.5))   = 0.25
        _K2HCardinalWeight   ("Cardinal Weight",    Range(0, 0.3))     = 0.125
        _K2HDiagonalWeight   ("Diagonal Weight",    Range(0, 0.1))     = 0.0625
        _K2HEdgeColor            ("Edge Color",       Color)             = (0,0,0,1)

        [Header(NPR Effect  Toon Shader)]
        _ToonColorBands        ("Color Bands",        Range(2, 8))   = 4.0
        _ToonPosterizeStrength ("Posterize Strength", Range(0, 1))   = 0.85
        _ToonSaturation        ("Saturation",         Range(0, 3))   = 1.0

        [Header(NPR Effect  Toon Sobel technique)]
        _TSColorBands        ("Color Bands",        Range(2, 8))       = 4.0
        _TSPosterizeStrength ("Posterize Strength", Range(0, 1))       = 0.85
        _TSSaturation        ("Saturation",         Range(0, 3))       = 1.0
        [Toggle] _TSEnableGaussBlur ("Enable Gaussian Blur", Float)    = 1
        _TSSobelSampleDist   ("Sobel Sample Dist",  Range(0, 10))      = 1.0
        _TSBlurRadius        ("Blur Radius",         Range(0, 5))      = 1.0
        _TSCenterWeight      ("Center Weight",       Range(0.1, 0.5))  = 0.25
        _TSCardinalWeight    ("Cardinal Weight",     Range(0, 0.3))    = 0.125
        _TSDiagonalWeight    ("Diagonal Weight",     Range(0, 0.1))    = 0.0625
        _TSThreshold         ("Edge Threshold",      Range(0, 0.5))    = 0.15
        _TSThreshMin         ("Thresh Min Mult",     Range(0, 1))      = 0.5
        _TSThreshMax         ("Thresh Max Mult",     Range(1, 5))      = 1.5
        _TSTightness         ("Tightness",           Range(0, 1))      = 0.2
        _TSPowerCurve        ("Power Curve",         Range(0.5, 5))    = 1.5
        _TSSobelStrength     ("Edge Strength",       Range(0, 1))      = 1.0

        [Header(NPR Effect  Toon Hierarchical technique)]
        _THColorBands        ("Color Bands",         Range(2, 8))       = 4.0
        _THPosterizeStrength ("Posterize Strength",  Range(0, 1))       = 0.85
        _THSaturation        ("Saturation",          Range(0, 3))       = 1.0
        _THDepthThreshold    ("Depth Threshold",     Range(0.001, 0.2)) = 0.02
        _THNormalThreshold   ("Normal Threshold",    Range(0.05, 1))    = 0.3
        _THColorThreshold    ("Color Threshold",     Range(0.01, 0.5))  = 0.1
        _THDepthWeight       ("Depth Weight",        Range(0, 1))       = 0.8
        _THNormalWeight      ("Normal Weight",       Range(0, 1))       = 0.8
        _THColorWeight       ("Color Weight",        Range(0, 1))       = 0.6
        _THEdgeWidth         ("Edge Width",          Range(0.5, 10))    = 1.5
        _THAdaptiveStrength  ("Adaptive Strength",   Range(0, 1))       = 0.5
        _THHierTightness     ("Hier Tightness",      Range(0, 1))       = 0.5
        _THHStrength         ("Hier Edge Strength",  Range(0, 1))       = 1.0
        [Toggle] _THEnableGaussBlur ("Color Blur",   Float)             = 0
        _THBlurRadius        ("Color Blur Radius",   Range(0, 5))       = 1.0
        _THCenterWeight      ("Center Weight",       Range(0.1, 0.5))   = 0.25
        _THCardinalWeight    ("Cardinal Weight",     Range(0, 0.3))     = 0.125
        _THDiagonalWeight    ("Diagonal Weight",     Range(0, 0.1))     = 0.0625
        _THEdgeColor         ("Edge Color",          Color)             = (0,0,0,1)

        [Header(NPR Effect Halftone technique)]
        _HTScale             ("Dot Scale",           Range(2, 100))     = 30.0
        _HTSharpness         ("Dot Sharpness",       Range(1, 50))      = 10.0
        _HTAngle             ("Grid Angle",          Range(0, 90))      = 45.0
        _HTToneBias          ("Tone Bias",           Range(-0.5, 0.5))  = 0.0
        _HTBrightCutoff      ("Bright Cutoff",       Range(0, 0.95))    = 0.4
        _HTInkColor          ("Ink Color",           Color)             = (0.05, 0.05, 0.1, 1)
        _HTPaperColor        ("Paper Color",         Color)             = (0.95, 0.93, 0.88, 1)
        _HTTextureInfluence  ("Texture Influence",   Range(0, 1))       = 0.5
        _HTStrength          ("Strength",            Range(0, 1))       = 1.0

        [Header(NPR Effect Hatching technique)]
        _HatScale            ("Hatch Scale",         Range(1, 100))     = 20.0
        _HatAngle            ("Primary Angle",       Range(0, 180))     = 45.0
        _HatCrossAngle       ("Cross Angle",         Range(0, 180))     = 135.0
        _HatThickness        ("Line Thickness",      Range(0.01, 0.5))  = 0.15
        _HatToneBias         ("Tone Bias",           Range(-0.5, 0.5))  = 0.0
        _HatBrightCutoff     ("Bright Cutoff",       Range(0, 0.95))    = 0.4
        _HatInkColor         ("Ink Color",           Color)             = (0.05, 0.05, 0.1, 1)
        _HatPaperColor       ("Paper Color",         Color)             = (0.95, 0.93, 0.88, 1)
        _HatTextureInfluence ("Texture Influence",   Range(0, 1))       = 0.5
        _HatStrength         ("Strength",            Range(0, 1))       = 1.0

        [Header(NPR Effect XToon 2D Ramp  V2 technique)]
        _XToonRamp              ("2D Toon Ramp (U=NdotL, V=Abstraction)", 2D) = "white" {}
        _XToonLightSensitivity  ("Light Sensitivity",   Range(0.0, 1.0))  = 1.0
        _XToonRampSmoothing     ("Ramp Edge Smoothing", Range(0.0, 0.1))  = 0.01
        _XToonShadowColor       ("Shadow Color",        Color)            = (0.25, 0.25, 0.35, 1)
        _XToonShadowStrength    ("Shadow Strength",     Range(0.0, 1.0))  = 0.6
        _XToonDetailMode        ("Detail Mode (0=Depth 1=Curv 2=Manual)", Range(0, 2)) = 0
        _XToonDetailBias        ("Detail Bias",         Range(0.0, 1.0))  = 0.5
        _XToonDepthNear         ("Depth Near",          Float)            = 5.0
        _XToonDepthFar          ("Depth Far",           Float)            = 50.0
        _XToonManualDetail      ("Manual Detail",       Range(0.0, 1.0))  = 0.0
        _XToonSpecularColor     ("Specular Color",      Color)            = (1,1,1,1)
        _XToonSpecularSize      ("Specular Size",       Range(0.0, 1.0))  = 0.03
        _XToonSpecularSmoothness("Specular Smoothness", Range(0.001, 0.5))= 0.02
        _XToonSpecularStrength  ("Specular Strength",   Range(0.0, 1.0))  = 0.5
        _XToonLightingStrength  ("Lighting Strength",   Range(0.0, 1.0))  = 1.0
        [Toggle] _XToonEnableRim("Enable Rim Light",    Float)            = 0
        _XToonRimColor          ("Rim Color",           Color)            = (1,1,1,1)
        _XToonRimPower          ("Rim Power",           Range(0.5, 10.0)) = 3.0
        _XToonRimThreshold      ("Rim Threshold",       Range(0, 1))      = 0.1
        _XToonRimStrength       ("Rim Strength",        Range(0.0, 1.0))  = 0.3
        _XToonNormalSmoothing   ("Normal Smoothing",    Range(0.0, 1.0))  = 0.0
        [Toggle] _XToonEnableSobel("Enable Sobel Edges", Float)           = 0
        _XToonSobelEdgeColor    ("Sobel Edge Color",    Color)            = (0,0,0,1)
        _XToonSobelThreshold    ("Sobel Threshold",     Range(0.001, 1))  = 0.15
        _XToonSobelSampleDist   ("Sobel Sample Dist",   Range(0.1, 10))   = 1.0
        _XToonSobelStrength     ("Sobel Strength",      Range(0.0, 1.0))  = 1.0

        [Header(NPR Inverted Hull Outline)]
        [Toggle] _OutlineEnabled ("Enable Outline", Float) = 1
        _OutlineWidth   ("Outline Width (world units)", Range(0, 0.05)) = 0.003
        _OutlineColor   ("Outline Color",   Color)         = (0,0,0,1)
    }

    // Universal Render Pipeline (URP), shader target 5.0
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque" }
        Pass
        {
            PackageRequirements
            {
              "com.unity.render-pipelines.universal" : "10.1.0"
            }
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma editor_sync_compilation // avoid showing the "invalid" teal Unity shader during loading

            #pragma vertex Vertex_main_instancing
            #pragma fragment Fragment_main

            // 5.0 required for SV_Coverage, 3.5 required for SV_VertexID
            #pragma target 5.0

            #pragma shader_feature UNITY_PIPELINE_URP      // Works before Unity 2021
			      #define UNITY_PIPELINE_URP      // Works after Unity 2021

			      #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            #include_with_pragmas "app_specific/app_variants.hlsl"   // replace this with an app_specific declarations file
            #include "app_specific/app_declarations.hlsl"   // replace this with an app_specific declarations file
            #include_with_pragmas "Style2MetaAvatarCore.hlsl"
            #include "app_specific/app_functions.hlsl"   // replace this with an app_specific functions file
            ENDHLSL
        }

        Pass
        {
            Name "MotionVectors"
            Tags{ "LightMode" = "MotionVectors"}
            Tags { "RenderType" = "Opaque" }

            HLSLPROGRAM

            #pragma target 3.5 // necessary for use of SV_VertexID
            #pragma multi_compile _ APPLICATION_SPACE_WARP_MOTION
            #pragma vertex OvrMotionVectorsVertProgram
            #pragma fragment OvrMotionVectorsFragProgram
            #include "Packages/com.meta.xr.sdk.avatars/Scripts/ShaderUtils/OvrAvatarMotionVectorsCore.hlsl"

            ENDHLSL
        }

        Pass
        {
            Name "XRMotionVectors"
            Tags { "LightMode" = "XRMotionVectors" }
            ColorMask RGBA

            // Stencil write for obj motion pixels
            Stencil
            {
                WriteMask 1
                Ref 1
                Comp Always
                Pass Replace
            }

            HLSLPROGRAM
            #define APPLICATION_SPACE_WARP_MOTION 1
            #pragma target 3.5 // necessary for use of SV_VertexID
            #pragma vertex OvrMotionVectorsVertProgram
            #pragma fragment OvrMotionVectorsFragProgram
            #include "Packages/com.meta.xr.sdk.avatars/Scripts/ShaderUtils/OvrAvatarMotionVectorsCore.hlsl"

            ENDHLSL
        }

        Pass
        {
            Name "NPROutline"
            Tags { "LightMode" = "SRPDefaultUnlit" }
            Cull Front
            ZWrite Off
            ZTest LEqual

            HLSLPROGRAM
            #pragma editor_sync_compilation

            #pragma vertex Vertex_main_instancing
            #pragma fragment Fragment_main

            #pragma target 5.0
            #define OUTLINE_PASS 1

            #pragma shader_feature UNITY_PIPELINE_URP
            #define UNITY_PIPELINE_URP

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            #include_with_pragmas "app_specific/app_variants.hlsl"
            #include "app_specific/app_declarations.hlsl"
            #include_with_pragmas "Style2MetaAvatarCore.hlsl"
            #include "app_specific/app_functions.hlsl"
            ENDHLSL
        }
    }

    // Unity Built-in Render Pipeline, shader target 5.0
    SubShader
    {
        Tags { "RenderPipeline" = "" "RenderType" = "Opaque" }
        LOD 100
        Cull[_Cull]

        // Single Light
        Pass
        {
            Tags { "LightMode" = "ForwardBase" }

            CGPROGRAM
            #pragma editor_sync_compilation // avoid showing the "invalid" teal Unity shader during loading

            #pragma vertex Vertex_main_instancing
            #pragma fragment Fragment_main

            // 5.0 required for SV_Coverage, 3.5 required for SV_VertexID
            #pragma target 5.0
            #include_with_pragmas "app_specific/app_variants.hlsl"   // replace this with an app_specific declarations file
            #include "app_specific/app_declarations.hlsl"   // replace this with an app_specific declarations file
            #include_with_pragmas "Style2MetaAvatarCore.hlsl"
            #include "app_specific/app_functions.hlsl"   // replace this with an app_specific functions file
            ENDCG
        }

        // Up to 4 Additive Lights
        Pass
        {
            Tags { "LightMode" = "ForwardAdd" }
            Blend One One
            ZWrite Off

            CGPROGRAM
            #pragma editor_sync_compilation // avoid showing the "invalid" teal Unity shader during loading

            #pragma vertex Vertex_main_instancing
            #pragma fragment Fragment_main

            // 5.0 required for SV_Coverage, 3.5 required for SV_VertexID
            #pragma target 5.0
            #include_with_pragmas "app_specific/app_variants.hlsl"   // replace this with an app_specific declarations file
            #include "app_specific/app_declarations.hlsl"   // replace this with an app_specific declarations file
            #include_with_pragmas "Style2MetaAvatarCore.hlsl"
            #include "app_specific/app_functions.hlsl"   // replace this with an app_specific functions file
            ENDCG
        }

        Pass
        {
            Name "NPROutline"
            Cull Front
            ZWrite Off
            ZTest LEqual

            CGPROGRAM
            #pragma editor_sync_compilation

            #pragma vertex Vertex_main_instancing
            #pragma fragment Fragment_main

            #pragma target 5.0
            #define OUTLINE_PASS 1

            #include_with_pragmas "app_specific/app_variants.hlsl"
            #include "app_specific/app_declarations.hlsl"
            #include_with_pragmas "Style2MetaAvatarCore.hlsl"
            #include "app_specific/app_functions.hlsl"
            ENDCG
        }
    }

    // Universal Render Pipeline (URP), shader target 3.5 compatibility mode
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque" }
        Pass
        {
            PackageRequirements
            {
              "com.unity.render-pipelines.universal" : "10.1.0"
            }
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma editor_sync_compilation // avoid showing the "invalid" teal Unity shader during loading

            #pragma vertex Vertex_main_instancing
            #pragma fragment Fragment_main

            #pragma target 3.5

            #pragma shader_feature UNITY_PIPELINE_URP      // Works before Unity 2021
            #define UNITY_PIPELINE_URP      // Works after Unity 2021

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            #include_with_pragmas "app_specific/app_variants.hlsl"   // replace this with an app_specific declarations file
            #include "app_specific/app_declarations.hlsl"   // replace this with an app_specific declarations file
            #include_with_pragmas "Style2MetaAvatarCore.hlsl"
            #include "app_specific/app_functions.hlsl"   // replace this with an app_specific functions file
            ENDHLSL
        }

        Pass
        {
            Name "MotionVectors"
            Tags{ "LightMode" = "MotionVectors"}
            Tags { "RenderType" = "Opaque" }

            HLSLPROGRAM

            #pragma target 3.5 // necessary for use of SV_VertexID
            #pragma multi_compile _ APPLICATION_SPACE_WARP_MOTION
            #pragma vertex OvrMotionVectorsVertProgram
            #pragma fragment OvrMotionVectorsFragProgram
            #include "Packages/com.meta.xr.sdk.avatars/Scripts/ShaderUtils/OvrAvatarMotionVectorsCore.hlsl"

            ENDHLSL
        }

        Pass
        {
            Name "XRMotionVectors"
            Tags { "LightMode" = "XRMotionVectors" }
            ColorMask RGBA

            // Stencil write for obj motion pixels
            Stencil
            {
                WriteMask 1
                Ref 1
                Comp Always
                Pass Replace
            }

            HLSLPROGRAM
            #define APPLICATION_SPACE_WARP_MOTION 1
            #pragma target 3.5 // necessary for use of SV_VertexID
            #pragma vertex OvrMotionVectorsVertProgram
            #pragma fragment OvrMotionVectorsFragProgram
            #include "Packages/com.meta.xr.sdk.avatars/Scripts/ShaderUtils/OvrAvatarMotionVectorsCore.hlsl"

            ENDHLSL
        }

        Pass
        {
            Name "NPROutline"
            Tags { "LightMode" = "SRPDefaultUnlit" }
            Cull Front
            ZWrite Off
            ZTest LEqual

            HLSLPROGRAM
            #pragma editor_sync_compilation

            #pragma vertex Vertex_main_instancing
            #pragma fragment Fragment_main

            #pragma target 3.5
            #define OUTLINE_PASS 1

            #pragma shader_feature UNITY_PIPELINE_URP
            #define UNITY_PIPELINE_URP

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            #include_with_pragmas "app_specific/app_variants.hlsl"
            #include "app_specific/app_declarations.hlsl"
            #include_with_pragmas "Style2MetaAvatarCore.hlsl"
            #include "app_specific/app_functions.hlsl"
            ENDHLSL
        }
    }

    // Unity Built-in Render Pipeline, shader target 3.5 compatibility mode
    SubShader
    {
        Tags { "RenderPipeline" = "" "RenderType" = "Opaque" }
        LOD 100
        Cull[_Cull]

        // Single Light
        Pass
        {
            Tags { "LightMode" = "ForwardBase" }

            CGPROGRAM
            #pragma editor_sync_compilation // avoid showing the "invalid" teal Unity shader during loading

            #pragma vertex Vertex_main_instancing
            #pragma fragment Fragment_main

            #pragma target 3.5
            #include_with_pragmas "app_specific/app_variants.hlsl"   // replace this with an app_specific declarations file
            #include "app_specific/app_declarations.hlsl"   // replace this with an app_specific declarations file
            #include_with_pragmas "Style2MetaAvatarCore.hlsl"
            #include "app_specific/app_functions.hlsl"   // replace this with an app_specific functions file
            ENDCG
        }

        // Up to 4 Additive Lights
        Pass
        {
            Tags { "LightMode" = "ForwardAdd" }
            Blend One One
            ZWrite Off

            CGPROGRAM
            #pragma editor_sync_compilation // avoid showing the "invalid" teal Unity shader during loading

            #pragma vertex Vertex_main_instancing
            #pragma fragment Fragment_main

            #pragma target 3.5
            #include_with_pragmas "app_specific/app_variants.hlsl"   // replace this with an app_specific declarations file
            #include "app_specific/app_declarations.hlsl"   // replace this with an app_specific declarations file
            #include_with_pragmas "Style2MetaAvatarCore.hlsl"
            #include "app_specific/app_functions.hlsl"   // replace this with an app_specific functions file
            ENDCG
        }

        Pass
        {
            Name "NPROutline"
            Cull Front
            ZWrite Off
            ZTest LEqual

            CGPROGRAM
            #pragma editor_sync_compilation

            #pragma vertex Vertex_main_instancing
            #pragma fragment Fragment_main

            #pragma target 3.5
            #define OUTLINE_PASS 1

            #include_with_pragmas "app_specific/app_variants.hlsl"
            #include "app_specific/app_declarations.hlsl"
            #include_with_pragmas "Style2MetaAvatarCore.hlsl"
            #include "app_specific/app_functions.hlsl"
            ENDCG
        }
    }
}
