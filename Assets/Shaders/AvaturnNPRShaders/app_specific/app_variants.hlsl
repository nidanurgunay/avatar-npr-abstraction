// NPR Sobel variant configuration — mirrors the SDK default app_variants.hlsl.
// All style variants are compiled so the shader works with any avatar profile.

#pragma multi_compile STYLE_1_LIGHT STYLE_1_STANDARD STYLE_2_LIGHT STYLE_2_STANDARD STYLE_2_EXPERIMENTAL

#if defined(STYLE_1_LIGHT)
    #define EYE_GLINTS_ON
    #define SKIN_ON
#elif defined(STYLE_1_STANDARD)
    #define EYE_GLINTS_ON
    #define SKIN_ON
    #define HAS_NORMAL_MAP_ON
#elif defined(STYLE_2_LIGHT)
    #define EYE_GLINTS_ON
    #define SKIN_ON
    #define HAS_NORMAL_MAP_ON
    #define SIMPLE_OCCLUSION
#elif defined(STYLE_2_STANDARD)
    #define EYE_GLINTS_ON
    #define SKIN_ON
    #define HAS_NORMAL_MAP_ON
    #define ENABLE_HAIR_ON
    #define ENABLE_RIM_LIGHT_ON
    #define SSS_CURVATURE
#else // STYLE_2_EXPERIMENTAL
    #define EYE_GLINTS_ON
    #define SKIN_ON
    #define HAS_NORMAL_MAP_ON
    #define ENABLE_HAIR_ON
    #define ENABLE_RIM_LIGHT_ON
    #define SSS_CURVATURE
#endif

#pragma multi_compile MATERIAL_MODE_TEXTURE MATERIAL_MODE_VERTEX
#pragma multi_compile EXTERNAL_BUFFERS_ENABLED EXTERNAL_BUFFERS_DISABLED
#pragma multi_compile __ DEBUG_MODE_ON
