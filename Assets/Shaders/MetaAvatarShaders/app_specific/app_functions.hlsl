// App specific functions — called from Style2MetaAvatarCore.hlsl via forward declarations.
// This file should persist across successive SDK integrations.

// MOD START MetaNPR: master NPR toggle keyword
#pragma multi_compile __ ENABLE_NPR_EDGES
// MOD END MetaNPR

// MOD START MetaNPR: technique selection (mutually exclusive; default = Derivative)
#pragma multi_compile __ EFFECT_SOBEL EFFECT_NORMAL_EDGE EFFECT_GAUSS_SOBEL EFFECT_HIERARCHICAL EFFECT_KUWAHARA EFFECT_KUWAHARA_SOBEL EFFECT_KUW_GAUSS_HIER EFFECT_TOON EFFECT_TOON_SOBEL EFFECT_TOON_HIER EFFECT_HALFTONE EFFECT_HATCHING EFFECT_XTOON
// XToon detail-axis mode (matches Jade/Avaturn [KeywordEnum(Depth, Curvature, Manual)])
#pragma multi_compile _DETAILMODE_DEPTH _DETAILMODE_CURVATURE _DETAILMODE_MANUAL
// MOD END MetaNPR

// MOD START MetaNPR: include the active technique (excluded from outline pass — outline needs no edge code)
#if defined(ENABLE_NPR_EDGES) && !defined(OUTLINE_PASS)
  #if defined(EFFECT_SOBEL)
    #include "../NPREffect_Sobel.cginc"
  #elif defined(EFFECT_NORMAL_EDGE)
    #include "../NPREffect_NormalEdge.cginc"
  #elif defined(EFFECT_GAUSS_SOBEL)
    #include "../NPREffect_GaussianSobel.cginc"
  #elif defined(EFFECT_HIERARCHICAL)
    #include "../NPREffect_Hierarchical.cginc"
  #elif defined(EFFECT_KUWAHARA)
    #include "../NPREffect_Kuwahara2.cginc"
  #elif defined(EFFECT_KUWAHARA_SOBEL)
    #include "../NPREffect_Kuwahara2Sobel.cginc"
  #elif defined(EFFECT_KUW_GAUSS_HIER)
    #include "../NPREffect_Kuwahara2GaussHier.cginc"
  #elif defined(EFFECT_TOON)
    #include "../NPREffect_Toon.cginc"
  #elif defined(EFFECT_TOON_SOBEL)
    #include "../NPREffect_ToonSobel.cginc"
  #elif defined(EFFECT_TOON_HIER)
    #include "../NPREffect_ToonGaussHier.cginc"
  #elif defined(EFFECT_HALFTONE)
    #include "../NPREffect_Halftone.cginc"
  #elif defined(EFFECT_HATCHING)
    #include "../NPREffect_Hatching.cginc"
  #elif defined(EFFECT_XTOON)
    #include "../NPREffect_XToon.cginc"
  #else
    #include "../AvatarNPREdgeEffect.cginc"
  #endif
#endif
// MOD END MetaNPR

float  _OutlineEnabled;
float  _OutlineWidth;
float4 _OutlineColor;

void AppSpecificVertexPostManipulation(AvatarVertexInput i, inout VertexToFragment o) {
// MOD START MetaNPR: inverted hull - push skinned vertex outward along world normal
#if defined(OUTLINE_PASS)
    float3 worldNorm = normalize((float3)o.v_Normal);
    float3 worldPos  = (float3)o.v_WorldPos + worldNorm * _OutlineWidth;
    o.v_Vertex = mul(UNITY_MATRIX_VP, float4(worldPos, 1.0));
#endif
// MOD END MetaNPR
}

void AppSpecificPreManipulation(inout avatar_FragmentInput i) {
    // Call app specific functions from here.
}

void AppSpecificFragmentComponentManipulation(avatar_FragmentInput i, inout float3 punctualSpecular,
    inout float3 punctualDiffuse, inout float3 ambientSpecular, inout float3 ambientDiffuse) {
    // Call app specific functions from here.
}

// MOD START MetaNPR: apply NPR edge effect in post-manipulation hook
void AppSpecificPostManipulation(avatar_FragmentInput i, inout avatar_FragmentOutput o) {

// Inverted hull outline pass: output outline colour and skip all edge detection
#if defined(OUTLINE_PASS)
    if (_OutlineEnabled < 0.5) discard;
    o.color = _OutlineColor;
    return;
#endif

#if defined(ENABLE_NPR_EDGES) && !defined(OUTLINE_PASS)
  #if defined(EFFECT_SOBEL) || defined(EFFECT_NORMAL_EDGE) || defined(EFFECT_GAUSS_SOBEL) || defined(EFFECT_HIERARCHICAL) || defined(EFFECT_KUWAHARA) || defined(EFFECT_KUWAHARA_SOBEL) || defined(EFFECT_KUW_GAUSS_HIER) || defined(EFFECT_TOON) || defined(EFFECT_TOON_SOBEL) || defined(EFFECT_TOON_HIER) || defined(EFFECT_HALFTONE) || defined(EFFECT_HATCHING) || defined(EFFECT_XTOON)
    #if defined(EFFECT_XTOON) || defined(EFFECT_HIERARCHICAL)
    // XToon and Hierarchical need positionWS for depth — pass it as 5th arg.
    o.color = ApplyNPREffect(o.color, i.geometry.texcoord_0,
                             i.geometry.normal, i.geometry.worldViewDir,
                             (float3)i.geometry.positionInWorldSpace);
    #else
    o.color = ApplyNPREffect(o.color, i.geometry.texcoord_0,
                             i.geometry.normal, i.geometry.worldViewDir);
    #endif
  #else
    o.color = ApplyNPREdgeEffect(o.color, i.geometry.texcoord_0);
  #endif
#endif

}
// MOD END MetaNPR
